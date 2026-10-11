"""Verible format / lint and Verilator: run them, translate their output into Diags.

The configs ship inside the package and are always passed explicitly, so a
user repo needs no config of its own. Tool diagnostics that map to no house
rule pass through as `EXT-VL-<rule>` / `EXT-VLTR-<CODE>` at SHOULD, so gaps in
the rules DB stay visible (`svstyle rules --unmapped`).
"""

import re
import shutil
import subprocess
import tempfile
from collections.abc import Sequence
from pathlib import Path

from .rules import Diag, Rule, tool_index

# A new Verible can shift alignment by a column, which breaks `fix`
# idempotency on files formatted by the old one. Drift warns, never fails.
KNOWN_GOOD_VERIBLE_VERSION = "v0.0-3946-g851d3ff4"

DATA = Path(__file__).parent / "data"
FORMAT_FLAGS = DATA / "verible-format.flags"
LINT_CONFIG = DATA / "rules.verible_lint"

VERIBLE_LINT_RE = re.compile(
    r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+)(?:-(?P<end>\d+))?: (?P<msg>.*?)"
    r"(?: \[Style: [^\]]*\])? \[(?P<rule>[a-z0-9-]+)\]$"
)
# pyslang accepted the file before Verible saw it, so this is Verible's parser
# falling short, not the author's bug: say so, at SHOULD, instead of going quiet.
VERIBLE_SYNTAX_RE = re.compile(
    r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+)(?:-\d+)?: (?P<msg>syntax error.*)$"
)
# The Verible findings `svstyle fix` resolves: the formatter's whitespace, and
# the legacy constructs fix.py rewrites. Everything else Verible reports, even
# under a rule marked autofix (line-length, genvar placement), stays the author's.
FIXED_BY_FIX = {
    "no-tabs", "no-trailing-spaces", "posix-eof", "explicit-begin", "endif-comment",
    "legacy-generate-region", "explicit-function-lifetime", "explicit-task-lifetime",
    "always-comb",
}  # fmt: skip
NOT_NBA_RE = re.compile(r"^(\w+) should be driven by a nonblocking assignment")
# Verible wants a bare name on the left; `s_q.field <=` is a field of a `_q` flop.
FIELD_OF_Q_RE = re.compile(r"^\w+_q(\.\w+)+ Should be a simple reference")
PACKAGE_RE = re.compile(r"^\s*package\s+\w+\s*;", re.MULTILINE)
# The code is optional: elaboration errors (an undeclared name under
# `default_nettype none) print as a bare `%Error:`.
VERILATOR_RE = re.compile(
    r"^%(?P<kind>Warning|Error)(?:-(?P<code>[A-Z0-9_]+))?: "
    r"(?P<path>.+?):(?P<line>\d+):(?P<col>\d+): (?P<msg>.*)$"
)
# Errors that are expected when checking part of a design, so they stay SHOULD.
SOFT_ERRORS = {"MODMISSING"}


TIMEOUT = 600  # seconds; a hung tool must not hang CI


STDIN_LOC_RE = re.compile(r"^-?:?\s*<stdin>:(?P<line>\d+):\d+(?:-\d+)?:\s*")


class ToolMissing(Exception):
    """A required external tool is not on PATH (exit 2)."""


class ToolFailed(Exception):
    """An external tool ran but could not do its job."""


def _run(tool: str, args: list[str], stdin: str | None = None) -> subprocess.CompletedProcess:
    exe = shutil.which(tool)
    if exe is None:
        raise ToolMissing(f"{tool} not found on PATH")
    try:
        return subprocess.run(
            [exe, *args], input=stdin, capture_output=True, text=True, timeout=TIMEOUT
        )
    except subprocess.TimeoutExpired as exc:
        raise ToolFailed(f"{tool} timed out after {TIMEOUT} s") from exc


def verible_version() -> str | None:
    out = _run("verible-verilog-format", ["--version"]).stdout
    m = re.search(r"^Version\s+(\S+)", out, re.MULTILINE)
    return m.group(1) if m else None


def verible_format(text: str) -> str:
    res = _run("verible-verilog-format", [f"--flagfile={FORMAT_FLAGS}", "-"], stdin=text)
    # Verible exits 0 on a syntax error and echoes the input; stderr is the tell.
    if res.returncode != 0 or res.stderr.strip():
        # On non-convergence Verible dumps the whole file twice; the first line says why.
        first = res.stderr.strip().splitlines()[0][:200] if res.stderr.strip() else ""
        if m := STDIN_LOC_RE.match(first):
            # slang parsed the file first, so this is Verible's parser falling short.
            first = f"Verible cannot parse line {m['line']} (slang can): {first[m.end() :]}"
        raise ToolFailed(first or f"verible-verilog-format exit {res.returncode}")
    return res.stdout


def verible_verify(paths: list[str], rules: list[Rule]) -> list[Diag]:
    """One FMT-002 finding per file the formatter would change."""
    sev = next(r.severity for r in rules if r.id == "FMT-002")
    out = []
    for p in paths:
        res = _run("verible-verilog-format", [f"--flagfile={FORMAT_FLAGS}", "--verify", p])
        if "failed to converge" in res.stderr:
            # --verify exits 0 here, so a naive check would call the file formatted.
            msg = "Verible cannot format this file (does not converge); lay it out by hand"
            out.append(Diag(p, 1, 1, "FMT-002", sev, msg))
        elif res.returncode != 0:
            out.append(Diag(p, 1, 1, "FMT-002", sev, "file needs formatting", fixable=True))
    return out


def verible_lint(paths: list[str], rules: list[Rule]) -> list[Diag]:
    res = _run("verible-verilog-lint", [f"--rules_config={LINT_CONFIG}", *paths])
    lines = {p: Path(p).read_text(encoding="utf-8").splitlines() for p in paths}
    diags = parse_verible_lint(res.stdout + res.stderr, rules, lines)  # findings go to stderr
    return [
        d
        for d in diags
        if not _optional_register(d)
        and not (d.rule == "NAM-004" and FIELD_OF_Q_RE.match(d.message))
    ]


def _optional_register(d: Diag) -> bool:
    """A `_q` tied off in one generate branch and a flop in another is still a flop."""
    m = NOT_NBA_RE.match(d.message)
    if d.rule != "NAM-004" or not m:
        return False
    text = Path(d.path).read_text(encoding="utf-8")
    return re.search(rf"^\s*{re.escape(m.group(1))}\s*<=", text, re.MULTILINE) is not None


def packages_first(paths: list[str]) -> list[str]:
    """Verilator and Yosys resolve `pkg::name` in file order, so packages go first."""
    return sorted(paths, key=lambda p: not PACKAGE_RE.search(Path(p).read_text(encoding="utf-8")))


def verilator_lint(
    paths: list[str], rules: list[Rule], include_dirs: Sequence[str] = ()
) -> list[Diag]:
    # MULTITOP: checking a set of files is not elaborating a design top.
    dirs = dict.fromkeys([*include_dirs, *(str(Path(p).parent) for p in paths)])
    # PINCONNECTEMPTY: `.q_o()` is the explicit no-connect PRT-004 asks for.
    args = ["--lint-only", "-Wall", "-Wno-fatal", "-Wno-context", "-Wno-MULTITOP"]
    args += ["-Wno-PINCONNECTEMPTY"] + [f"-I{d}" for d in dirs] + packages_first(paths)
    res = _run("verilator", args)
    diags = parse_verilator(res.stderr, rules)
    lines = res.stderr.splitlines()
    located = any((m := VERILATOR_RE.match(ln)) and m.group("kind") == "Error" for ln in lines)
    if res.returncode != 0 and not located:
        # Failed without saying where: the design did not elaborate, so its
        # silence about everything else is not a clean bill.
        why = next((ln for ln in lines if ln.startswith("%Error")), "")
        why = why or f"verilator exit {res.returncode}"
        diags.append(Diag(paths[0], 1, 1, "EXT-VLTR-ERROR", "MUST", why))
    # Verilator also lints submodules it finds on its own; report only what was asked.
    asked = {Path(p).resolve() for p in paths}
    # A package's constants are used by modules elsewhere in the design, so
    # "unused" means nothing when the package is linted without them.
    packages = {
        Path(p).resolve() for p in paths if PACKAGE_RE.search(Path(p).read_text(encoding="utf-8"))
    }
    return [
        d
        for d in diags
        if (path := Path(d.path).resolve()) in asked
        and not (path in packages and d.rule == "EXT-VLTR-UNUSEDPARAM")
    ]


def parse_verible_lint(
    output: str, rules: list[Rule], lines: dict[str, list[str]] | None = None
) -> list[Diag]:
    """`lines`: the sources, to name what a finding points at (Verible's own
    messages say "Signal name does not match", not which one)."""
    index = tool_index(rules, "verible-lint")
    out = []
    for line in output.splitlines():
        if m := VERIBLE_LINT_RE.match(line):
            span = _span(m, lines or {})
            name = m.group("rule")
            if rule := index.get(name):
                # `fix` leaves a .v file Verilog, so no always_comb there.
                sv = m.group("path").endswith((".sv", ".svh"))
                fixable = name in FIXED_BY_FIX and (sv or name != "always-comb")
                out.append(_diag(m, rule.id, rule.severity, fixable, span))
            else:
                out.append(_diag(m, "EXT-VL-" + name, "SHOULD", span=span))
        elif m := VERIBLE_SYNTAX_RE.match(line):
            msg = f"Verible cannot parse this; its lint rules were not checked: {m.group('msg')}"
            out.append(Diag(m.group("path"), int(m.group("line")), int(m.group("col")),
                            "EXT-VL-syntax", "SHOULD", msg))  # fmt: skip
    return out


def parse_verilator(output: str, rules: list[Rule]) -> list[Diag]:
    index = tool_index(rules, "verilator")
    out = []
    for line in output.splitlines():
        if not (m := VERILATOR_RE.match(line)):
            continue
        code = m.group("code") or "ERROR"
        if rule := index.get(code):
            out.append(_diag(m, rule.id, rule.severity))
        else:
            hard = m.group("kind") == "Error" and code not in SOFT_ERRORS
            out.append(_diag(m, "EXT-VLTR-" + code, "MUST" if hard else "SHOULD"))
    return out


def _span(m: re.Match, lines: dict[str, list[str]]) -> str:
    """The identifier a Verible finding points at, if the span is one."""
    src, no = lines.get(m.group("path"), []), int(m.group("line"))
    if not m.group("end") or not 0 < no <= len(src):
        return ""
    text = src[no - 1][int(m.group("col")) - 1 : int(m.group("end"))]
    return text if re.fullmatch(r"\w+", text) and text not in m.group("msg") else ""


def _diag(m: re.Match, rule: str, severity: str, fixable: bool = False, span: str = "") -> Diag:
    msg = f"`{span}`: {m.group('msg')}" if span else m.group("msg")
    return Diag(
        m.group("path"), int(m.group("line")), int(m.group("col")), rule, severity, msg,
        fixable=fixable,
    )  # fmt: skip


# --- Yosys: `check --synth` -----------------------------------------------------
# Verilator --lint-only does not look for combinational loops; synthesis does.
# Yosys's own SystemVerilog frontend reads less than slang; a file it cannot
# read is reported as unchecked (MUST): synthesis was not checked.

YOSYS_WARNINGS = {
    "found logic loop": "logic-loop",
    "multiple conflicting drivers": "multiple-drivers",
    "used but has no driver": "no-driver",
}
YOSYS_SRC_RE = re.compile(r"source: (?P<path>.+?):(?P<line>\d+)\.(?P<col>\d+)")
YOSYS_ERROR_RE = re.compile(r"^(?P<path>.+?):(?P<line>\d+): ERROR: (?P<msg>.*)$")


def yosys_check(
    paths: list[str], rules: list[Rule], include_dirs: Sequence[str] = (), partial: bool = False
) -> list[Diag]:
    """`partial`: a module the files instantiate is not among them (a black box)."""
    dirs = dict.fromkeys([*include_dirs, *(str(Path(p).parent) for p in paths)])
    paths = packages_first(paths)
    with tempfile.TemporaryDirectory(prefix="svstyle") as tmp:
        # Files are quoted, but Yosys takes no quoted -I: a dir with a space is
        # reached through a symlink whose path has none.
        incs = []
        for i, d in enumerate(dirs):
            if re.search(r"\s", d):
                link = Path(tmp) / f"inc{i}"
                link.symlink_to(Path(d).resolve(), target_is_directory=True)
                d = str(link)
            incs.append(f"-I{d}")
        read = "read_verilog -sv " + " ".join([*incs, *(f'"{p}"' for p in paths)])
        res = _run("yosys", ["-q", "-p", f"{read}; hierarchy; proc; check"])
    out = res.stdout + res.stderr
    diags = parse_yosys(out, rules, paths[0], partial)
    if res.returncode != 0 and not any(d.rule == "EXT-YOSYS-read" for d in diags):
        # Failed without saying where: synthesis was not checked, so do not pass.
        why = next((ln for ln in out.splitlines() if "ERROR" in ln), f"yosys exit {res.returncode}")
        msg = f"Yosys failed; synthesis was not checked: {why}"
        diags.append(Diag(paths[0], 1, 1, "EXT-YOSYS-read", "MUST", msg))
    return diags


def parse_yosys(output: str, rules: list[Rule], fallback: str, partial: bool = False) -> list[Diag]:
    index = tool_index(rules, "yosys")
    out: list[Diag] = []
    lines = output.splitlines()
    for i, line in enumerate(lines):
        if m := YOSYS_ERROR_RE.match(line):
            msg = f"Yosys cannot read this; synthesis was not checked: {m.group('msg')}"
            out.append(
                Diag(m.group("path"), int(m.group("line")), 1, "EXT-YOSYS-read", "MUST", msg)
            )
            continue
        if not line.startswith("Warning: "):
            continue
        msg = line[len("Warning: ") :].rstrip(":")
        name = next((n for key, n in YOSYS_WARNINGS.items() if key in msg), "warning")
        # The cells that make up the finding follow, each with its source location.
        path, ln, col = fallback, 1, 1
        for follow in lines[i + 1 :]:
            if follow.startswith("Warning: "):
                break
            if src := YOSYS_SRC_RE.search(follow):
                path, ln, col = src.group("path"), int(src.group("line")), int(src.group("col"))
                break
        rule = index.get(name)
        rid, sev = (rule.id, rule.severity) if rule else ("EXT-YOSYS-" + name, "SHOULD")
        if partial and name == "no-driver":
            # Driven, most likely, by the missing module; Verilator's MODMISSING is SHOULD too.
            sev, msg = "SHOULD", msg + " (a submodule was not passed; is it driven there?)"
        out.append(Diag(path, ln, col, rid, sev, msg))
    return out
