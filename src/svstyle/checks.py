"""The rules no external tool covers: header, comments, port style, default_nettype.

Each check reports under its tool-side rule name (`rule="port_comment"`),
mapped to the house rule ID through rules.toml; `svstyle rules --check` greps
for those names, so a rule without an implementation here fails CI.
Autofixable findings carry an insert-only `fix = (offset, text)`.
"""

import re
from datetime import date

from .parse import Source, parse
from .rules import Diag, Rule, tool_index

# Set this to your company. While it is the placeholder, every header svstyle
# writes carries it, and DOC-001 warns until it is replaced by hand.
PLACEHOLDER = "<Company>"
COMPANY = PLACEHOLDER

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


def run_checks(text: str, path: str, rules: list[Rule]) -> list[Diag]:
    """All svstyle-owned findings for one file. Raises ParseError if it does not parse."""
    src = parse(text, path)
    ctx = _Ctx(path, tool_index(rules, "svstyle"))
    check_header(ctx, text)
    check_default_nettype(ctx, text)
    check_comments(ctx, src)
    check_ports(ctx, src)
    return sorted(ctx.out, key=lambda d: d.line)


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


def check_header(ctx: _Ctx, text: str) -> None:
    m = HEADER_RE.match(text)
    if m is None:
        if OURS_RE.match(text):
            ctx.emit(rule="header", line=1, message="file header is malformed")
        else:
            # A foreign licence header stays; ours goes above it.
            header = HEADER.format(year=date.today().year, company=COMPANY)
            ctx.emit(rule="header", line=1, message="missing file header", fix=(0, header))
        return
    if m.group("company") == PLACEHOLDER:
        ctx.emit(
            rule="header", line=1, severity="SHOULD",
            message=f"header company is still the placeholder {PLACEHOLDER}",
        )  # fmt: skip
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
        if a.comment is not None:
            continue
        trailing = (a.offset, TODO_TRAILING) if a.fixable else None
        above = (a.offset, TODO_ABOVE) if a.fixable else None
        missing = f"`{a.name}` has no trailing // comment"
        if a.kind == "port":
            ctx.emit(rule="port_comment", line=a.line, message=missing, fix=trailing)
        elif a.kind in ("param", "decl"):
            ctx.emit(rule="decl_comment", line=a.line, message=missing, fix=trailing)
        elif a.kind == "block":
            msg = f"no // comment above `{a.name}` block"
            ctx.emit(rule="block_comment", line=a.line, message=msg, fix=above)
        else:
            msg = f"no // comment above instance `{a.name}`"
            ctx.emit(rule="instance_comment", line=a.line, message=msg, fix=above)


def check_ports(ctx: _Ctx, src: Source) -> None:
    for name, line in src.non_ansi:
        ctx.emit(rule="ansi_ports", line=line, message=f"module `{name}` uses non-ANSI ports")
    for a in src.anchors:
        if a.kind == "port" and ", " in a.name:
            ctx.emit(rule="ansi_ports", line=a.line, message=f"one port per line: {a.name}")
        if a.kind == "instance" and a.detail != "named":
            ctx.emit(
                rule="named_ports", line=a.line,
                message=f"instance `{a.name}` connects ports {a.detail}, not by name",
            )  # fmt: skip
