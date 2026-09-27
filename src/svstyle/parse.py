"""The pyslang layer: parse a file and list the places the DOC-* rules anchor to.

An anchor is a line that needs a comment. Declarations (ports, parameters,
signals) want a trailing `//` comment on their line; always blocks and
instances want a `//` comment on the line above. The checks read `comment`;
`svstyle fix` inserts at `offset`.

Everything is line-based because `fix` runs Verible first, which puts each
declaration, block and instance on its own line.
"""

from dataclasses import dataclass

from pyslang import DiagnosticEngine
from pyslang.parsing import TriviaKind
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


class ParseError(Exception):
    """The file does not parse; `svstyle` refuses to touch it (exit 3)."""


@dataclass(frozen=True)
class Anchor:
    kind: str  # port | param | decl | block | instance
    name: str  # declared names joined by ", "; the keyword for blocks
    line: int  # 1-based line that owns the comment
    comment: str | None  # the `//` comment found there, if any
    offset: int  # insertion point: end of line's last token, or start of the line above-anchors use
    detail: str = ""  # instances: named | ordered | wildcard | mixed
    fixable: bool = True  # False inside macro expansions or preprocessor-split port lists


@dataclass
class Source:
    text: str
    anchors: list[Anchor]
    non_ansi: list[tuple[str, int]]  # (module name, line) of non-ANSI port lists


def parse(text: str, name: str = "source.sv") -> Source:
    tree = SyntaxTree.fromText(text, name)
    sm = tree.sourceManager
    errors = [d for d in tree.diagnostics if d.isError()]
    if errors:
        engine = DiagnosticEngine(sm)
        raise ParseError(
            "\n".join(
                f"{name}:{sm.getLineNumber(d.location)}:{sm.getColumnNumber(d.location)}: "
                f"{engine.formatMessage(d)}"
                for d in errors
            )
        )
    return _Walker(tree, text).run()


def _tokens(node: SyntaxNode) -> list:
    out: list = []
    node.visit(lambda x: out.append(x) if not isinstance(x, SyntaxNode) else None)
    return out


class _Walker:
    def __init__(self, tree: SyntaxTree, text: str):
        self.sm = tree.sourceManager
        self.text = text
        self.root = tree.root
        self.toks = _tokens(self.root)
        # Last token index on each line, for the trailing-comment lookup.
        self.last_on_line = {self.line(t): i for i, t in enumerate(self.toks)}
        self.anchors: list[Anchor] = []
        self.non_ansi: list[tuple[str, int]] = []

    def run(self) -> Source:
        self.walk(self.root, split_list=False)
        return Source(self.text, self.anchors, self.non_ansi)

    def line(self, tok) -> int:
        return self.sm.getLineNumber(tok.location)

    def offset(self, tok) -> int:
        loc = tok.location
        return self.sm.getExpansionLoc(loc).offset if self.sm.isMacroLoc(loc) else loc.offset

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
        if k in (K.AnsiPortList, K.ParameterPortList):
            # A directive inside the list means lines appear and vanish per
            # configuration; inserting comments there is not safe.
            split_list = any(
                tr.kind == TriviaKind.Directive for t in _tokens(node)[1:] for tr in t.trivia
            )
        if k in DECLS or k in PARAMS or k in PORTS:
            kind = "port" if k in PORTS else "param" if k in PARAMS else "decl"
            self.trailing(node, kind, _decl_names(node), split_list)
            return
        if k in BLOCKS:
            self.above(node, "block", node.getFirstToken().rawText)
            return
        if k == K.HierarchyInstantiation:
            names = ", ".join(i.decl.name.valueText for i in node.instances if i.decl)
            styles = {
                CONNECTION_STYLE[c.kind]
                for i in node.instances
                for c in i.connections
                if c.kind in CONNECTION_STYLE
            }
            style = styles.pop() if len(styles) == 1 else "mixed" if styles else "named"
            self.above(node, "instance", names, style)
            return
        for child in node:
            if isinstance(child, SyntaxNode):
                self.walk(child, split_list)

    def trailing(self, node: SyntaxNode, kind: str, name: str, split_list: bool) -> None:
        line = self.line(node.getLastToken())
        i = self.last_on_line[line]
        last = self.toks[i]
        comment = None
        if i + 1 < len(self.toks):
            for tr in self.toks[i + 1].trivia:
                if tr.kind == TriviaKind.LineComment:
                    comment = tr.getRawText()
                if tr.kind != TriviaKind.Whitespace:
                    break
        fixable = not (split_list or self.in_macro(node))
        end = self.offset(last) + len(last.rawText)
        prev = self.anchors[-1] if self.anchors else None
        if prev and (prev.kind, prev.line) == (kind, line):
            # `input logic a_i, b_i,` is two port nodes but one line, one comment.
            name = f"{prev.name}, {name}"
            fixable = fixable and prev.fixable
            self.anchors.pop()
        self.anchors.append(Anchor(kind, name, line, comment, end, fixable=fixable))

    def above(self, node: SyntaxNode, kind: str, name: str, detail: str = "") -> None:
        first = node.getFirstToken()
        start = self.offset(first)
        line_start = self.text.rfind("\n", 0, start) + 1
        comment = _comment_above(
            list(first.trivia), is_first=first.location == self.toks[0].location
        )
        self.anchors.append(
            Anchor(
                kind, name, self.line(first), comment, line_start, detail,
                fixable=not self.in_macro(node),
            )
        )  # fmt: skip


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
    return ", ".join(d.name.valueText for d in node.declarators)
