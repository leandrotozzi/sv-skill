"""The pyslang layer: parse a file and list the places the DOC-* rules anchor to.

An anchor is a line that needs a comment. Declarations (ports, parameters,
signals) want a trailing `//` comment on their line; always blocks and
instances want a `//` comment on the line above. The checks read `comment`;
`svstyle fix` inserts at `offset`.

Everything is line-based because `fix` runs Verible first, which puts each
declaration, block and instance on its own line.
"""

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field

from pyslang import Bag, BumpAllocator, DiagnosticEngine, Diagnostics, Diags, SourceManager
from pyslang.ast import Compilation, SymbolKind
from pyslang.parsing import Lexer, PreprocessorOptions, TokenKind, TriviaKind
from pyslang.syntax import SyntaxKind, SyntaxNode, SyntaxTree

K = SyntaxKind

DECLS = {K.DataDeclaration, K.NetDeclaration, K.ParameterDeclarationStatement}
PARAMS = {K.ParameterDeclaration, K.TypeParameterDeclaration}
PORTS = {K.ImplicitAnsiPort, K.ExplicitAnsiPort}
BLOCKS = {K.AlwaysFFBlock, K.AlwaysCombBlock, K.AlwaysLatchBlock}
# Declarations inside these are locals, not the module's contract.
OPAQUE = {
    K.AlwaysBlock, K.InitialBlock, K.FinalBlock, K.FunctionDeclaration,
    K.TaskDeclaration, K.ClassDeclaration,
}  # fmt: skip
CONNECTION_STYLE = {
    K.NamedPortConnection: "named",
    K.OrderedPortConnection: "ordered",
    K.EmptyPortConnection: "ordered",
    K.WildcardPortConnection: "wildcard",
}


COLUMN_LIMIT = 100  # Verible's --column_limit and line-length (FMT-002)


class ParseError(Exception):
    """The file does not parse; `svstyle` refuses to touch it (exit 3)."""


@dataclass(frozen=True)
class Anchor:
    kind: str  # port | param | decl | block | instance
    name: str  # declared names joined by ", "; the keyword for blocks
    line: int  # 1-based line that owns the comment
    comment: str | None  # the `//` comment found there, if any
    offset: int  # insertion point: end of line's last token, or start of the line above-anchors use
    detail: str = ""  # instances: named | ordered | wildcard | mixed; ports: continued
    fixable: bool = True  # False inside macro expansions or preprocessor-split port lists
    # A lone `//` line directly above a declaration that fits on its line with it:
    # (start offset, length) of that line, and the comment, for `fix` to move.
    above: tuple[int, int, str] | None = None


@dataclass
class Source:
    text: str
    anchors: list[Anchor]
    non_ansi: list[tuple[str, int]]  # (module name, line) of non-ANSI port lists
    port_lists: list[list[tuple[str, int]]] = field(default_factory=list)  # (name, line) per module
    file_imports: list[int] = field(default_factory=list)  # lines of file-scope `import`
    # always_ff: (line, [(edge, signal)], first `if` predicate or None)
    ff_blocks: list[tuple[int, list[tuple[str, str]], str | None]] = field(default_factory=list)
    # Plain `always` other than `@*`: (line, "edge" | "list", fix or None). The
    # fix makes an edge block always_ff; None when that would change behaviour.
    legacy_always: list[tuple[int, str, tuple | None]] = field(default_factory=list)
    # Offsets of `wire` keywords that can become `logic` without changing
    # meaning. Not an inout port, and no initialiser: `wire x = a;` is an assign
    # while `logic x = a;` is only an initial value. Wires the tree cannot see
    # (macros, disabled `ifdef` text) are never listed.
    safe_wires: set[int] = field(default_factory=set)
    # The safe wires that also carry a data type (`wire logic x`), which Verible
    # cannot parse: offset -> length up to the type, so `fix` deletes the `wire`.
    typed_wires: dict[int, int] = field(default_factory=dict)
    # Modules defined here: name -> (port names in order, the inout ones), and the
    # module types this file instantiates. Across files they tell `fix` which nets
    # reach an inout, and `check` whether the design is complete.
    ports: dict[str, tuple[list[str], set[str]]] = field(default_factory=dict)
    instantiated: set[str] = field(default_factory=set)
    # `initial` blocks written in this file, outside macros and `ifdef regions.
    initial_lines: list[int] = field(default_factory=list)
    # Token-rewriting fixes for code the formatter cannot touch: (offset, text, cut).
    rewrites: list[tuple[int, str, int]] = field(default_factory=list)


EDGE_RE = re.compile(r"\b(posedge|negedge)\s+(\w+)")
DIRECTIVE_LINE_RE = re.compile(r"^[ \t]*`(ifdef|ifndef|elsif|else|endif)\b[ \t]*(\w*)(.*)$")


def conditional_lines(text: str) -> set[int]:
    """1-based lines inside any `ifdef / `ifndef region, directives included."""
    out, depth = set(), 0
    for no, ln in enumerate(text.splitlines(), 1):
        m = DIRECTIVE_LINE_RE.match(ln)
        if m and m.group(1) in ("ifdef", "ifndef"):
            depth += 1
        if depth:
            out.add(no)
        if m and m.group(1) == "endif":
            depth = max(depth - 1, 0)
    return out


def char_offsets(text: str):
    """slang counts byte offsets; Python indexes characters. Map one to the other."""
    if text.isascii():
        return lambda b: b
    table = [i for i, ch in enumerate(text) for _ in ch.encode()] + [len(text)]
    return table.__getitem__


def raw_tokens(text: str) -> list[tuple[TokenKind, str, int]]:
    """(kind, text, offset) of every token of `text`, from the raw lexer.

    No preprocessing: directives and `ifdef`-disabled text are tokens too. Plain
    tuples, because a pyslang Token dies with the allocator that lexed it.
    """
    sm = SourceManager()
    alloc = BumpAllocator()
    lexer = Lexer(sm.assignText("raw.sv", text), alloc, Diagnostics(), sm)
    char = char_offsets(text)
    out = []
    while (tok := lexer.lex()).kind != TokenKind.EndOfFile:
        out.append((tok.kind, tok.rawText, char(tok.location.offset)))
    return out


def parse(
    text: str,
    name: str = "source.sv",
    include_dirs: Sequence[str] = (),
    ports: Mapping[str, tuple[list[str], set[str]]] | None = None,
) -> Source:
    """Parse `text` as the file `name`; includes resolve next to it and on `include_dirs`.

    `ports` describes modules defined in other files (`Source.ports`), so a
    `wire` connected to one of their inouts stays a `wire`.
    """
    opts = PreprocessorOptions()
    opts.additionalIncludePaths = list(include_dirs)
    tree = SyntaxTree.fromText(text, SourceManager(), name, name, Bag([opts]))
    sm = tree.sourceManager
    errors = [d for d in tree.diagnostics if d.isError()]
    if errors:
        engine = DiagnosticEngine(sm)
        msg = "\n".join(
            f"{name}:{sm.getLineNumber(d.location)}:{sm.getColumnNumber(d.location)}: "
            f"{engine.formatMessage(d)}"
            for d in errors
        )
        if any(d.code == Diags.CouldNotOpenIncludeFile for d in errors):
            msg += "\n(an `include was not found: pass its directory with -I DIR)"
        raise ParseError(msg)
    return _Walker(tree, text, ports or {}).run()


def implicit_nets(text: str, name: str, include_dirs: Sequence[str] = ()) -> list[str]:
    """Nets the code uses without declaring them; `default_nettype none` would break them.

    Elaborates the file on its own: modules it instantiates from elsewhere are
    unknown, which slang tolerates, and nets on their ports still show up.
    """
    opts = PreprocessorOptions()
    opts.additionalIncludePaths = list(include_dirs)
    # Every pyslang object here must stay referenced until the visit is done.
    sm = SourceManager()
    tree = SyntaxTree.fromText(text, sm, name, name, Bag([opts]))
    comp = Compilation()
    comp.addSyntaxTree(tree)
    found: list[str] = []

    def visit(sym) -> bool:
        if getattr(sym, "kind", None) == SymbolKind.Net and sym.isImplicit:
            found.append(sym.name)
        return True

    comp.getRoot().visit(visit)
    return sorted(set(found))


def _tokens(node: SyntaxNode) -> list:
    out: list = []
    node.visit(lambda x: out.append(x) if not isinstance(x, SyntaxNode) else None)
    return out


class _Walker:
    def __init__(self, tree: SyntaxTree, text: str, ports: Mapping):
        self.sm = tree.sourceManager
        self.text = text
        self.char = char_offsets(text)
        self.other_ports = ports
        self.root = tree.root
        # Zero-width tokens (the implicit type of `b_i` in `a_i, b_i`) carry no
        # trivia and sit on no line of their own; the lookups below skip them.
        # Tokens pulled in by `include belong to another file, with that file's
        # line numbers; only this file's tokens (and macro expansions in it) count.
        self.main = self.root.getLastToken().location.buffer  # EOF of this file
        self.toks = [
            t
            for t in _tokens(self.root)
            if (t.rawText or t.kind == TokenKind.EndOfFile) and self.is_main(t)
        ]
        # Last token index on each line, for the trailing-comment lookup.
        self.last_on_line = {self.line(t): i for i, t in enumerate(self.toks)}
        self.anchors: list[Anchor] = []
        self.non_ansi: list[tuple[str, int]] = []
        self.src = Source(text, self.anchors, self.non_ansi)
        self.guarded = conditional_lines(text)

    def run(self) -> Source:
        self.walk(self.root, split_list=False)
        self.resolved, self.initial_vars = _resolved_and_initial(self.root)
        self.design_ports()
        self.modernise(self.root)
        # A file with one design unit parses to that unit as the root; only a
        # CompilationUnit's members are at file scope.
        if self.root.kind == K.CompilationUnit:
            self.src.file_imports = [
                self.line(m.getFirstToken())
                for m in self.root.members
                if m.kind == K.PackageImportDeclaration and self.is_main(m.getFirstToken())
            ]
        return self.src

    def modernise(self, node: SyntaxNode) -> None:
        """Collect the legacy constructs `fix` may rewrite, over the whole tree.

        Only this file's own text, outside macro expansions and preprocessor
        splits, is ever rewritten; everything else is reported and left alone.
        """
        k = node.kind
        first = node.getFirstToken()
        if k == K.ClassDeclaration or (
            first is not None and first.rawText and not self.is_main(first)
        ):
            return
        # Containers are always entered; anything smaller that a macro or an
        # `ifdef reaches into is left exactly as written.
        containers = (K.ModuleDeclaration, K.CompilationUnit, K.PackageDeclaration)
        if k not in containers and (self.in_macro(node) or self.has_directive(node)):
            return
        if k == K.NetDeclaration and node.netType.rawText == "wire":
            decls = [d for d in node.declarators if isinstance(d, SyntaxNode)]
            if not any(d.initializer or d.name.rawText in self.resolved for d in decls):
                self.safe_wire(node.netType, node.type)
        elif k == K.ImplicitAnsiPort and node.header.kind == K.NetPortHeader:
            h = node.header
            if (
                h.netType.rawText == "wire"
                and h.direction.rawText != "inout"
                and not node.declarator.initializer
                and node.declarator.name.rawText not in self.resolved
            ):
                self.safe_wire(h.netType, h.dataType)
        elif k == K.AlwaysBlock:
            self.legacy_always(node)
        elif k == K.InitialBlock:
            line = self.line(node.getFirstToken())
            if line not in self.guarded:
                self.src.initial_lines.append(line)
        elif k == K.GenerateRegion:
            for tok in (node.keyword, node.endgenerate):
                self.delete_line_or_token(tok)
        elif (
            k in (K.FunctionDeclaration, K.TaskDeclaration) and not node.prototype.lifetime.rawText
        ):
            kw = node.prototype.keyword
            self.src.rewrites.append((self.offset(kw) + len(kw.rawText), " automatic", 0))
        for body in _bodies(node):
            if body.kind != K.SequentialBlockStatement and not self.in_macro(body):
                last = body.getLastToken()
                self.src.rewrites.append((self.offset(body.getFirstToken()), "begin ", 0))
                self.src.rewrites.append((self.offset(last) + len(last.rawText), " end", 0))
        for child in node:
            if isinstance(child, SyntaxNode):
                self.modernise(child)

    def has_directive(self, node: SyntaxNode) -> bool:
        return any(tr.kind == TriviaKind.Directive for t in _tokens(node)[1:] for tr in t.trivia)

    def legacy_always(self, node: SyntaxNode) -> None:
        stmt = node.statement
        line = self.line(node.keyword)
        if stmt.kind != K.TimingControlStatement:
            self.src.legacy_always.append((line, "list", None))
            return
        timing = str(stmt.timingControl).strip()
        kinds = {n.kind for n in _nodes(stmt.statement)}
        # Another timing control inside means it is not a flop or a comb block.
        nested = kinds & {K.TimingControlStatement, K.DelayControl}
        start = self.offset(node.keyword)
        if re.fullmatch(r"@\s*(\*|\(\s*\*\s*\))", timing):
            last = stmt.timingControl.getLastToken()
            cut = self.offset(last) + len(last.rawText) - start
            # Verible's always-comb reports this one; svstyle only rewrites it.
            if not nested:
                self.src.rewrites.append((start, "always_comb", cut))
        elif EDGE_RE.search(timing):
            # A variable an `initial` also writes cannot belong to an always_ff.
            shared = _assigned(stmt.statement) & self.initial_vars
            blocked = nested or K.AssignmentExpression in kinds or shared
            fix = None if blocked else (start, "always_ff", 6)
            self.src.legacy_always.append((line, "edge", fix))
        else:
            self.src.legacy_always.append((line, "list", None))

    def delete_line_or_token(self, tok) -> None:
        start = self.offset(tok)
        end = start + len(tok.rawText)
        line_start = self.text.rfind("\n", 0, start) + 1
        line_end = self.text.find("\n", end)
        line_end = len(self.text) if line_end == -1 else line_end + 1
        if not (self.text[line_start:start] + self.text[end:line_end]).strip():
            start, end = line_start, line_end  # alone on its line: drop the line
        self.src.rewrites.append((start, "", end - start))

    def record_ports(self, ports: SyntaxNode) -> None:
        names = []
        for p in ports.ports:
            if isinstance(p, SyntaxNode) and p.kind in PORTS:
                tok = (p.declarator if p.kind == K.ImplicitAnsiPort else p).name
                names.append((tok.valueText, self.line(tok)))
        self.src.port_lists.append(names)

    def record_ff(self, node: SyntaxNode) -> None:
        stmt = node.statement
        if stmt.kind != K.TimingControlStatement:
            return
        edges = EDGE_RE.findall(str(stmt.timingControl))
        body = stmt.statement
        if body.kind == K.SequentialBlockStatement and len(body.items):
            body = body.items[0]
        pred = str(body.predicate) if body.kind == K.ConditionalStatement else None
        self.src.ff_blocks.append((self.line(node.getFirstToken()), edges, pred))

    def design_ports(self) -> None:
        """Record ports and instances; nets on an inout must stay `wire`."""
        nodes = _nodes(self.root)
        for n in nodes:
            if n.kind in (K.ModuleDeclaration, K.InterfaceDeclaration):
                self.src.ports[n.header.name.valueText] = _module_ports(n)
        known = {**self.other_ports, **self.src.ports}
        for n in nodes:
            if n.kind != K.HierarchyInstantiation:
                continue
            kind = n.type.valueText
            self.src.instantiated.add(kind)
            order, inouts = known.get(kind, ([], set()))
            for inst in n.instances:
                conns = [c for c in inst.connections if isinstance(c, SyntaxNode)]
                for i, c in enumerate(conns):
                    if c.kind == K.NamedPortConnection:
                        port = c.name.valueText
                    elif c.kind == K.OrderedPortConnection:
                        port = order[i] if i < len(order) else None
                    else:
                        continue  # ponytail: `.*` is not followed; PRT-003 flags it anyway
                    if port in inouts and getattr(c, "expr", None) is not None:
                        self.resolved |= _identifiers(c.expr)

    def safe_wire(self, kw, data_type: SyntaxNode) -> None:
        start = self.offset(kw)
        self.src.safe_wires.add(start)
        if data_type.kind != K.ImplicitType:
            self.src.typed_wires[start] = self.offset(data_type.getFirstToken()) - start

    def is_main(self, tok) -> bool:
        return self.sm.getFullyExpandedLoc(tok.location).buffer == self.main

    def line(self, tok) -> int:
        return self.sm.getLineNumber(tok.location)

    def offset(self, tok) -> int:
        loc = tok.location
        loc = self.sm.getExpansionLoc(loc) if self.sm.isMacroLoc(loc) else loc
        return self.char(loc.offset)

    def from_assert_macro(self, tok) -> bool:
        loc = tok.location
        return self.sm.isMacroLoc(loc) and self.sm.getMacroName(loc).startswith("ASSERT")

    def in_macro(self, node: SyntaxNode) -> bool:
        return any(self.sm.isMacroLoc(t.location) for t in _tokens(node))

    def walk(self, node: SyntaxNode, split_list: bool) -> None:
        k = node.kind
        if k in OPAQUE:
            return
        if k == K.ModuleDeclaration and node.header.ports is not None:
            ports = node.header.ports
            if ports.kind == K.NonAnsiPortList:
                self.non_ansi.append((node.header.name.valueText, self.line(ports.getFirstToken())))
            elif ports.kind == K.AnsiPortList and self.is_main(node.getFirstToken()):
                self.record_ports(ports)
        if k in (K.AnsiPortList, K.ParameterPortList):
            # A directive inside the list means lines appear and vanish per
            # configuration; inserting comments there is not safe.
            split_list = any(
                tr.kind == TriviaKind.Directive for t in _tokens(node)[1:] for tr in t.trivia
            )
        first = node.getFirstToken()
        if first is not None and first.rawText and not self.is_main(first):
            return  # declared in an included file
        if first is not None and self.from_assert_macro(first):
            return  # the house assertion macros' own scaffolding, not the author's code
        if k in DECLS or k in PARAMS or k in PORTS:
            kind = "port" if k in PORTS else "param" if k in PARAMS else "decl"
            # `input logic a_i,\n b_i` - b_i has a zero-width type: it continues a_i's declaration.
            detail = "continued" if k in PORTS and not node.getFirstToken().rawText else ""
            self.trailing(node, kind, _decl_names(node), split_list, detail)
            return
        if k in BLOCKS:
            self.above(node, "block", node.getFirstToken().rawText)
            if k == K.AlwaysFFBlock:
                self.record_ff(node)
            return
        if k in (K.HierarchyInstantiation, K.BindDirective):
            # A bind's comment sits above `bind`, not above the module name after it.
            inst = node.instantiation if k == K.BindDirective else node
            names = ", ".join(i.decl.name.valueText for i in inst.instances if i.decl)
            styles = {
                CONNECTION_STYLE[c.kind]
                for i in inst.instances
                for c in i.connections
                if c.kind in CONNECTION_STYLE
            }
            style = styles.pop() if len(styles) == 1 else "mixed" if styles else "named"
            self.above(node, "instance", names, style)
            return
        for child in node:
            if isinstance(child, SyntaxNode):
                self.walk(child, split_list)

    def trailing(
        self, node: SyntaxNode, kind: str, name: str, split_list: bool, detail: str = ""
    ) -> None:
        first = node.getFirstToken()
        if self.sm.isMacroLoc(first.location):
            # The names only exist in the expansion; report what the author wrote.
            name = "`" + self.sm.getMacroName(first.location)
        line = self.line(node.getLastToken())
        i = self.last_on_line[line]
        last = self.toks[i]
        comment, moved = None, None
        if i + 1 < len(self.toks):
            for tr in _trivia(self.toks[i + 1]):
                if tr.kind == TriviaKind.LineComment:
                    comment = tr.getRawText()
                if tr.kind != TriviaKind.Whitespace:
                    break
        if comment is None:
            # A declaration spread over several lines has no one end to trail, and
            # one whose comment would not fit trailing within the column limit
            # (FMT-002) cannot carry it there: the line above will do for both.
            is_first = first.location == self.toks[0].location
            above = _comment_above(_trivia(first), is_first=is_first)
            width = len(self.text.splitlines()[line - 1].rstrip())
            if above and (self.line(first) != line or width + 2 + len(above) > COLUMN_LIMIT):
                comment = above
            elif above and "svstyle:" not in above:
                moved = self._lone_line_above(first, above)
        fixable = not (split_list or self.in_macro(node))
        end = self.offset(last) + len(last.rawText)
        prev = self.anchors[-1] if self.anchors else None
        if prev and (prev.kind, prev.line) == (kind, line):
            # `input logic a_i, b_i,` is two port nodes but one line, one comment.
            name = f"{prev.name}, {name}"
            fixable = fixable and prev.fixable
            detail = prev.detail
            self.anchors.pop()
            moved = None  # one comment line, two declarations: let the author decide
        self.anchors.append(Anchor(kind, name, line, comment, end, detail, fixable, moved))

    def _lone_line_above(self, first, comment: str) -> tuple[int, int, str] | None:
        """The comment's own line, if no other comment line sits right above it."""
        start = self.text.rfind("\n", 0, self.offset(first)) + 1  # this line
        top = self.text.rfind("\n", 0, max(start - 1, 0)) + 1  # the comment's line
        if self.text[top:start].strip() != comment:
            return None
        prev = self.text[self.text.rfind("\n", 0, max(top - 1, 0)) + 1 : top]
        return None if prev.lstrip().startswith("//") else (top, start - top, comment)

    def above(self, node: SyntaxNode, kind: str, name: str, detail: str = "") -> None:
        first = node.getFirstToken()
        start = self.offset(first)
        line_start = self.text.rfind("\n", 0, start) + 1
        comment = _comment_above(_trivia(first), is_first=first.location == self.toks[0].location)
        self.anchors.append(
            Anchor(
                kind, name, self.line(first), comment, line_start, detail,
                fixable=not self.in_macro(node),
            )
        )  # fmt: skip


ASSIGNS = {K.AssignmentExpression, K.NonblockingAssignmentExpression}
Z_RE = re.compile(r"'[sS]?[bBoOhH]?\s*[0-9a-fA-F_xX]*[zZ?]")


def _identifiers(node: SyntaxNode) -> set[str]:
    return {t.rawText for t in _tokens(node) if t.kind == TokenKind.Identifier}


def _assigned(node: SyntaxNode) -> set[str]:
    """Names on the left of every assignment under `node`; indices count too (conservative)."""
    return {name for n in _nodes(node) if n.kind in ASSIGNS for name in _identifiers(n.left)}


def _module_ports(mod: SyntaxNode) -> tuple[list[str], set[str]]:
    """(port names in order, the inout ones), ANSI or non-ANSI."""
    order: list[str] = []
    inouts: set[str] = set()
    ports = mod.header.ports
    if ports is None:
        return order, inouts
    direction = ""
    for p in ports.ports:
        if not isinstance(p, SyntaxNode):
            continue  # the commas
        if p.kind == K.ImplicitAnsiPort:
            # `inout wire a, b`: b's empty direction continues a's.
            d = getattr(p.header, "direction", None)  # an interface port has none
            direction = (d and d.rawText) or direction
            name = p.declarator.name.valueText
        elif p.kind == K.ExplicitAnsiPort:
            direction, name = p.direction.rawText or direction, p.name.valueText
        else:  # non-ANSI: the name here, the direction in the body
            name = next((t.rawText for t in _tokens(p) if t.kind == TokenKind.Identifier), "")
        order.append(name)
        if direction == "inout":
            inouts.add(name)
    for m in mod.members:
        if m.kind == K.PortDeclaration and m.header.direction.rawText == "inout":
            inouts |= {d.name.valueText for d in m.declarators if isinstance(d, SyntaxNode)}
    return order, inouts


def _resolved_and_initial(root: SyntaxNode) -> tuple[set[str], set[str]]:
    """Nets that must stay `wire` (two `assign`s, or one driving `z`), and names
    an `initial` writes. Per file, not per scope: a shared name only keeps more.

    ponytail: a `wire` tied to an `inout` of a module in another file still becomes
    `logic`; seeing that needs the whole design elaborated, not one file."""
    seen: set[str] = set()
    resolved: set[str] = set()
    initial: set[str] = set()
    for n in _nodes(root):
        if n.kind == K.ContinuousAssign:
            for a in n.assignments:
                names = _assigned(a)
                resolved |= names & seen
                seen |= names
                if Z_RE.search(str(a.right)):
                    resolved |= names
        elif n.kind == K.InitialBlock:
            initial |= _assigned(n)
    return resolved, initial


def _nodes(node: SyntaxNode) -> list[SyntaxNode]:
    out: list = []
    node.visit(lambda x: out.append(x) if isinstance(x, SyntaxNode) else None)
    return out


# Loop statements whose body Verible's explicit-begin wants wrapped.
LOOPS = {
    K.ForLoopStatement, K.LoopStatement, K.ForeverStatement, K.ForeachLoopStatement,
}  # fmt: skip
PROCESSES = {
    K.AlwaysBlock, K.AlwaysCombBlock, K.AlwaysFFBlock, K.AlwaysLatchBlock, K.InitialBlock,
}  # fmt: skip


def _bodies(node: SyntaxNode) -> list[SyntaxNode]:
    """The statements of `node` that explicit-begin wants inside begin/end.

    An `else if` is not one: the `if` is the else-branch's structure, and
    wrapping it would turn a flat chain into a staircase.
    """
    k = node.kind
    if k == K.ConditionalStatement:
        out = [node.statement]
        if node.elseClause is not None and node.elseClause.clause.kind != K.ConditionalStatement:
            out.append(node.elseClause.clause)
        return out
    if k in LOOPS:
        return [node.statement]
    if k in PROCESSES:
        stmt = node.statement
        return [stmt.statement if stmt.kind == K.TimingControlStatement else stmt]
    return []


def _trivia(tok) -> list:
    """A token's leading trivia, with each directive's own leading trivia spliced in.

    pyslang hangs `a;  // c` + `\n`ifdef X` as trivia of the `ifdef, not of the
    next token, so a comment right before a directive is only visible this way.
    """
    out = []
    for tr in tok.trivia:
        if tr.kind == TriviaKind.Directive:
            out += _trivia(tr.syntax().getFirstToken())
        out.append(tr)
    return out


def _comment_above(trivia: list, is_first: bool) -> str | None:
    """The `//` comment alone on the line directly above, or None."""
    i = len(trivia) - 1
    while i >= 0 and trivia[i].kind == TriviaKind.Whitespace:
        i -= 1
    if i < 1 or trivia[i].kind != TriviaKind.EndOfLine:
        return None
    i -= 1
    if trivia[i].kind != TriviaKind.LineComment:
        return None
    comment = trivia[i].getRawText()
    i -= 1
    while i >= 0 and trivia[i].kind == TriviaKind.Whitespace:
        i -= 1
    # Own line: preceded by a line break or directive, or it opens the file.
    if i < 0:
        return comment if is_first else None
    return comment if trivia[i].kind in (TriviaKind.EndOfLine, TriviaKind.Directive) else None


def _decl_names(node: SyntaxNode) -> str:
    k = node.kind
    if k in PORTS:
        decl = node.declarator if k == K.ImplicitAnsiPort else node
        return decl.name.valueText
    if k == K.ParameterDeclarationStatement:
        node = node.parameter
    return ", ".join(d.name.valueText for d in node.declarators if isinstance(d, SyntaxNode))
