"""The rules no external tool covers: header, comments, port style, default_nettype.

Each check reports under its tool-side rule name (`rule="port_comment"`),
mapped to the house rule ID through rules.toml; `svstyle rules --check` greps
for those names, so a rule without an implementation here fails CI.
Autofixable findings carry `fix = (offset, text)` to insert, or
`(offset, text, n)` to replace n characters (only ever inside a comment), or a
list of those applied together (moving a comment).
"""

import re
import tomllib
from collections.abc import Sequence
from datetime import date
from pathlib import Path

from pyslang.parsing import TokenKind

from .parse import Source, parse, raw_tokens
from .rules import Diag, Rule, tool_index

# Without a `.svstyle.toml` naming the company, headers carry this placeholder
# and DOC-001 warns until it is replaced.
PLACEHOLDER = "<Company>"
CONFIG_NAME = ".svstyle.toml"
CONFIG_KEYS = {"company": str, "select": list, "ignore": list, "include": list, "synth": str}


class ConfigError(Exception):
    """A `.svstyle.toml` is malformed (exit 2)."""


def load_config(path: str | Path) -> dict:
    """The nearest `.svstyle.toml` above `path`, like ruff finds `ruff.toml`; {} if none."""
    for d in Path(path).resolve().parents:
        cfg = d / CONFIG_NAME
        if cfg.is_file():
            try:
                data = tomllib.loads(cfg.read_text(encoding="utf-8"))
            except tomllib.TOMLDecodeError as e:
                raise ConfigError(f"{cfg}: {e}") from e
            for key, value in data.items():
                if key not in CONFIG_KEYS:
                    raise ConfigError(
                        f"{cfg}: unknown key {key!r} (known: {', '.join(CONFIG_KEYS)})"
                    )
                if not isinstance(value, CONFIG_KEYS[key]):
                    raise ConfigError(f"{cfg}: {key} must be a {CONFIG_KEYS[key].__name__}")
                if isinstance(value, list) and not all(isinstance(v, str) for v in value):
                    raise ConfigError(f"{cfg}: {key} must be a list of strings")
            # Include dirs are written relative to the config, like ruff's paths.
            if "include" in data:
                data["include"] = [str(d / inc) for inc in data["include"]]
            return data
    return {}


HEADER = (
    "// Copyright (c) {year} {company}\n"
    "// All rights reserved\n"
    "//\n"
    "// Description:\n"
    "//   TODO: describe\n"
    "\n"
)
HEADER_RE = re.compile(
    r"\A// Copyright \(c\) \d{4} (?P<company>.+)\n"
    r"// All rights reserved\n"
    r"//\n"
    r"// Description:\n"
    r"(?P<desc>(?://   .*\n)+)"
)
OURS_RE = re.compile(r"\A// Copyright \(c\) \d{4} ")
MIN_DESCRIPTION_WORDS = 5  # "Gray counter module." is a restatement, not a description
TODO_TRAILING = "  // TODO: describe"
TODO_ABOVE = "// TODO: describe\n"
HOW = {"ordered": "by position", "wildcard": "with .*", "mixed": "partly by position or .*"}

# ponytail: name heuristics for PRT-002; a clock or reset named otherwise ranks
# with "the rest" and is not checked. Waive or rename if one misfires.
CLOCK_RE = re.compile(r"(?:\w+_)?clk(?:_(?!en)\w+)?_i")
# A scan reset belongs to the DFT interface (with test_en_i), not the functional resets.
RESET_RE = re.compile(r"(?!scan_)(?:\w+_)?rst(?:_\w+)?_n?i")
SUFFIX_ORDER_RE = re.compile(r"_(?:i|o|io)n$")
RESET_NAME_RE = re.compile(r"\b\w*rst\w*\b")
DIRECTIVE_RE = re.compile(
    r"(?://|/\*).*\b(?:synopsys|synthesis|pragma|cadence|ambit)\b.*\b(full_case|parallel_case)\b"
    r"|\(\*[^)]*\b(full_case|parallel_case)\b"
)
LEGACY_NETS = {TokenKind.RegKeyword: "reg", TokenKind.WireKeyword: "wire"}


def run_checks(
    text: str,
    path: str,
    rules: list[Rule],
    include_dirs: Sequence[str] = (),
    company: str = PLACEHOLDER,
) -> list[Diag]:
    """All svstyle-owned findings for one file. Raises ParseError if it does not parse."""
    src = parse(text, path, include_dirs)
    ctx = _Ctx(path, tool_index(rules, "svstyle"))
    check_header(ctx, text, company)
    check_default_nettype(ctx, text)
    check_comments(ctx, src)
    check_ports(ctx, src)
    check_constructs(ctx, text, src)
    check_resets(ctx, src)
    return sorted(apply_waivers(ctx.out, text), key=lambda d: d.line)


# `// svstyle: waive LNG-001, DOC-004 <reason>`: on its own line it covers the
# next line, trailing it covers its own. The reason is required (DOC-009); a
# bare waiver is not recognised, so the finding stays.
WAIVER_RE = re.compile(
    r"//\s*svstyle:\s*waive\s+"
    r"(?P<ids>(?:[A-Z]{3}-\d{3}|EXT-[\w-]+)(?:\s*,\s*(?:[A-Z]{3}-\d{3}|EXT-[\w-]+))*)"
    r"\s+\S"
)


def waivers(text: str) -> dict[int, set[str]]:
    out: dict[int, set[str]] = {}
    for no, ln in enumerate(text.splitlines(), 1):
        if m := WAIVER_RE.search(ln):
            target = no + 1 if ln.lstrip().startswith("//") else no
            out.setdefault(target, set()).update(re.split(r"\s*,\s*", m.group("ids")))
    return out


def apply_waivers(diags: list[Diag], text: str) -> list[Diag]:
    waived = waivers(text)
    return [d for d in diags if d.rule not in waived.get(d.line, ())]


class _Ctx:
    def __init__(self, path: str, index: dict[str, Rule]):
        self.path = path
        self.index = index
        self.out: list[Diag] = []

    def emit(self, rule, line, message, fix=None, fixable=None, severity=None):
        r = self.index[rule]
        self.out.append(
            Diag(
                self.path, line, 1, r.id, severity or r.severity, message,
                fixable=fix is not None if fixable is None else fixable, fix=fix,
            )
        )  # fmt: skip


def check_header(ctx: _Ctx, text: str, company: str) -> None:
    m = HEADER_RE.match(text)
    if m is None:
        if OURS_RE.match(text):
            ctx.emit(rule="header", line=1, message="file header is malformed")
        else:
            # A foreign licence header stays; ours goes above it.
            header = HEADER.format(year=date.today().year, company=company)
            ctx.emit(rule="header", line=1, message="missing file header", fix=(0, header))
        return
    if m.group("company") == PLACEHOLDER:
        if company == PLACEHOLDER:
            msg = f"header company is still {PLACEHOLDER}; set company in {CONFIG_NAME}"
            ctx.emit(rule="header", line=1, severity="SHOULD", message=msg)
        else:
            fix = (m.start("company"), company, len(PLACEHOLDER))
            msg = f"header company is still {PLACEHOLDER}; {CONFIG_NAME} says {company}"
            ctx.emit(rule="header", line=1, severity="SHOULD", message=msg, fix=fix)
    desc = " ".join(ln[2:].strip() for ln in m.group("desc").splitlines())
    if desc.startswith("TODO") or len(desc.split()) < MIN_DESCRIPTION_WORDS:
        ctx.emit(
            rule="header_description", line=4,
            message="Description says too little; state what it does and its constraints",
        )  # fmt: skip


def check_default_nettype(ctx: _Ctx, text: str) -> None:
    if not ctx.path.endswith(".sv"):
        return
    lines = text.splitlines(keepends=True)
    offset = 0
    for no, ln in enumerate(lines, 1):
        if ln.strip() and not ln.lstrip().startswith("//"):
            if ln.strip() != "`default_nettype none":
                ctx.emit(
                    rule="default_nettype", line=no,
                    message="`default_nettype none must follow the header",
                    fix=(offset, "`default_nettype none\n\n"),
                )  # fmt: skip
            break
        offset += len(ln)
    code = [(no, ln) for no, ln in enumerate(lines, 1) if ln.strip()]
    if code and code[-1][1].strip() != "`resetall":
        sep = "" if text.endswith("\n") else "\n"
        ctx.emit(
            rule="default_nettype", line=code[-1][0],
            message="file must end with `resetall",
            fix=(len(text), sep + "\n`resetall\n"),
        )  # fmt: skip


def check_comments(ctx: _Ctx, src: Source) -> None:
    for a in src.anchors:
        if a.comment is not None and TODO_TRAILING.strip() not in a.comment:
            continue
        if a.comment is not None:
            # `fix` wrote it; only the author can replace it.
            trailing = above = None
            missing = f"`{a.name}` still has the `TODO: describe` placeholder; describe it"
            block = instance = missing
        else:
            trailing = (a.offset, TODO_TRAILING) if a.fixable else None
            if a.fixable and a.above:
                # The comment is there, one line too high: move it to the end.
                start, length, text = a.above
                trailing = [(start, "", length), (a.offset, "  " + text)]
            above = (a.offset, TODO_ABOVE) if a.fixable else None
            missing = f"`{a.name}` has no trailing // comment"
            block = f"no // comment above `{a.name}` block"
            instance = f"no // comment above instance `{a.name}`"
        if a.kind == "port":
            ctx.emit(rule="port_comment", line=a.line, message=missing, fix=trailing)
        elif a.kind in ("param", "decl"):
            ctx.emit(rule="decl_comment", line=a.line, message=missing, fix=trailing)
        elif a.kind == "block":
            ctx.emit(rule="block_comment", line=a.line, message=block, fix=above)
        else:
            ctx.emit(rule="instance_comment", line=a.line, message=instance, fix=above)


def check_ports(ctx: _Ctx, src: Source) -> None:
    for name, line in src.non_ansi:
        ctx.emit(rule="ansi_ports", line=line, message=f"module `{name}` uses non-ANSI ports")
    for ports in src.port_lists:
        check_port_order(ctx, ports)
        for name, line in ports:
            if SUFFIX_ORDER_RE.search(name):
                msg = f"`{name}`: the direction suffix goes last (`_ni`, not `_in`)"
                ctx.emit(rule="suffix_order", line=line, message=msg)
    for a in src.anchors:
        if a.kind == "port" and (", " in a.name or a.detail == "continued"):
            msg = f"one port per declaration, each with its own direction and type: {a.name}"
            ctx.emit(rule="ansi_ports", line=a.line, message=msg)
        if a.kind == "instance" and a.detail != "named":
            ctx.emit(
                rule="named_ports", line=a.line,
                message=f"instance `{a.name}` connects ports {HOW[a.detail]}, not by name",
            )  # fmt: skip


def check_port_order(ctx: _Ctx, ports: list[tuple[str, int]]) -> None:
    """Each clock opens a domain group -- its clock, its resets, then the rest --
    so a CDC module reads clk_wr_i, rst_wr_ni, ..., clk_rd_i, rst_rd_ni, ...
    The list opens with a clock; a reset never follows the rest of its group.
    """
    if not ports or not any(CLOCK_RE.fullmatch(n) for n, _ in ports):
        return
    name, line = ports[0]
    if not CLOCK_RE.fullmatch(name):
        msg = f"port list opens with `{name}`; clocks first, then resets, then the rest"
        ctx.emit(rule="port_order", line=line, message=msg)
        return
    rest = False
    for name, line in ports:
        if CLOCK_RE.fullmatch(name):
            rest = False
        elif not RESET_RE.fullmatch(name):
            rest = True
        elif rest:
            msg = f"reset `{name}` follows other ports; put it right after its clock"
            ctx.emit(rule="port_order", line=line, message=msg)
            return


def check_constructs(ctx: _Ctx, text: str, src: Source) -> None:
    for kind, _, offset in raw_tokens(text):
        if kw := LEGACY_NETS.get(kind):
            line = text.count("\n", 0, offset) + 1
            # `reg` is always a variable; a `wire` only when the tree says so.
            safe = kw == "reg" or offset in src.safe_wires
            fix = (offset, "logic", len(kw)) if safe else None
            if offset in src.typed_wires:  # `wire logic x`: the type is there, drop the `wire`
                fix = (offset, "", src.typed_wires[offset])
            msg = f"`{kw}`: declare `logic` instead"
            ctx.emit(rule="logic_only", line=line, message=msg, fix=fix)
    for line, kind, fix in src.legacy_always:
        if kind == "edge":
            msg = "clocked `always`: write `always_ff`" + (
                "" if fix else " (it has `=` or a delay)"
            )
            ctx.emit(rule="always_ff_style", line=line, message=msg, fix=fix)
        else:
            msg = (
                "`always` with a sensitivity list: write `always_comb`, which cannot miss a signal"
            )
            ctx.emit(rule="always_comb_style", line=line, message=msg)
    for no, ln in enumerate(text.splitlines(), 1):
        if m := DIRECTIVE_RE.search(ln):
            what = m.group(1) or m.group(2)
            msg = f"`{what}` directive: simulation and synthesis would see different logic"
            ctx.emit(rule="synthesis_directives", line=no, message=msg)
    for line in src.initial_lines:
        msg = "`initial` in RTL: synthesis ignores it; give state its value from reset"
        ctx.emit(rule="initial_block", line=line, message=msg)
    for line in src.file_imports:
        msg = "file-scope import leaks into every unit; import in the module header"
        ctx.emit(rule="import_scope", line=line, message=msg)


def check_resets(ctx: _Ctx, src: Source) -> None:
    for line, edges, pred in src.ff_blocks:
        high = [sig for edge, sig in edges if edge == "posedge" and RESET_NAME_RE.fullmatch(sig)]
        if high:
            msg = f"`posedge {high[0]}`: asynchronous resets are active-low (`negedge rst_ni`)"
            ctx.emit(rule="reset_style", line=line, message=msg)
        elif len(edges) == 1 and pred and RESET_NAME_RE.search(pred):
            msg = "synchronous reset; reset asynchronously: `@(posedge clk_i or negedge rst_ni)`"
            ctx.emit(rule="reset_style", line=line, message=msg)
