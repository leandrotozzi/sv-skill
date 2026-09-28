"""Verible format / lint and Verilator: run them, translate their output into Diags.

The configs ship inside the package and are always passed explicitly, so a
user repo needs no config of its own. Tool diagnostics that map to no house
rule pass through as `EXT-VL-<rule>` / `EXT-VLTR-<CODE>` at SHOULD, so gaps in
the rules DB stay visible (`svstyle rules --unmapped`).
"""

import re
import shutil
import subprocess
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
    r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+)(?:-\d+)?: (?P<msg>.*?)"
    r"(?: \[Style: [^\]]*\])? \[(?P<rule>[a-z0-9-]+)\]$"
)
# pyslang accepted the file before Verible saw it, so this is Verible's parser
# falling short, not the author's bug: say so, at SHOULD, instead of going quiet.
VERIBLE_SYNTAX_RE = re.compile(
    r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+)(?:-\d+)?: (?P<msg>syntax error.*)$"
)
PACKAGE_RE = re.compile(r"^\s*package\s+\w+\s*;", re.MULTILINE)
# The code is optional: elaboration errors (an undeclared name under
# `default_nettype none) print as a bare `%Error:`.
VERILATOR_RE = re.compile(
    r"^%(?P<kind>Warning|Error)(?:-(?P<code>[A-Z0-9_]+))?: "
    r"(?P<path>.+?):(?P<line>\d+):(?P<col>\d+): (?P<msg>.*)$"
)
# Errors that are expected when checking part of a design, so they stay SHOULD.
SOFT_ERRORS = {"MODMISSING"}


class ToolMissing(Exception):
    """A required external tool is not on PATH (exit 2)."""


class ToolFailed(Exception):
    """An external tool ran but could not do its job."""


def _run(tool: str, args: list[str], stdin: str | None = None) -> subprocess.CompletedProcess:
    exe = shutil.which(tool)
    if exe is None:
        raise ToolMissing(f"{tool} not found on PATH")
    return subprocess.run([exe, *args], input=stdin, capture_output=True, text=True)


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
    return parse_verible_lint(res.stdout + res.stderr, rules)  # findings go to stderr


def verilator_lint(
    paths: list[str], rules: list[Rule], include_dirs: Sequence[str] = ()
) -> list[Diag]:
    # MULTITOP: checking a set of files is not elaborating a design top.
    dirs = dict.fromkeys([*include_dirs, *(str(Path(p).parent) for p in paths)])
    # PINCONNECTEMPTY: `.q_o()` is the explicit no-connect PRT-004 asks for.
    args = ["--lint-only", "-Wall", "-Wno-fatal", "-Wno-context", "-Wno-MULTITOP"]
    args += ["-Wno-PINCONNECTEMPTY"] + [f"-I{d}" for d in dirs] + paths
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
    packages = {Path(p).resolve() for p in paths if PACKAGE_RE.search(Path(p).read_text())}
    return [
        d
        for d in diags
        if (path := Path(d.path).resolve()) in asked
        and not (path in packages and d.rule == "EXT-VLTR-UNUSEDPARAM")
    ]


def parse_verible_lint(output: str, rules: list[Rule]) -> list[Diag]:
    index = tool_index(rules, "verible-lint")
    out = []
    for line in output.splitlines():
        if m := VERIBLE_LINT_RE.match(line):
            rule = index.get(m.group("rule"))
            rid, sev = (rule.id, rule.severity) if rule else ("EXT-VL-" + m.group("rule"), "SHOULD")
            out.append(_diag(m, rid, sev))
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


def _diag(m: re.Match, rule: str, severity: str) -> Diag:
    return Diag(
        m.group("path"), int(m.group("line")), int(m.group("col")), rule, severity, m.group("msg")
    )
