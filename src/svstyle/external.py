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
PACKAGE_RE = re.compile(r"^\s*package\s+\w+\s*;", re.MULTILINE)
VERILATOR_RE = re.compile(
    r"^%(?:Warning|Error)-(?P<code>[A-Z0-9_]+): (?P<path>.+?):(?P<line>\d+):(?P<col>\d+): "
    r"(?P<msg>.*)$"
)


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
    args = ["--lint-only", "-Wall", "-Wno-fatal", "-Wno-context", "-Wno-MULTITOP"]
    args += [f"-I{d}" for d in dirs] + paths
    # Verilator also lints submodules it finds on its own; report only what was asked.
    asked = {Path(p).resolve() for p in paths}
    # A package's constants are used by modules elsewhere in the design, so
    # "unused" means nothing when the package is linted without them.
    packages = {Path(p).resolve() for p in paths if PACKAGE_RE.search(Path(p).read_text())}
    return [
        d
        for d in parse_verilator(_run("verilator", args).stderr, rules)
        if (path := Path(d.path).resolve()) in asked
        and not (path in packages and d.rule == "EXT-VLTR-UNUSEDPARAM")
    ]


def parse_verible_lint(output: str, rules: list[Rule]) -> list[Diag]:
    return _translate(VERIBLE_LINT_RE, output, tool_index(rules, "verible-lint"), "EXT-VL-")


def parse_verilator(output: str, rules: list[Rule]) -> list[Diag]:
    return _translate(VERILATOR_RE, output, tool_index(rules, "verilator"), "EXT-VLTR-")


def _translate(regex: re.Pattern, output: str, index: dict[str, Rule], prefix: str) -> list[Diag]:
    out = []
    for line in output.splitlines():
        m = regex.match(line)
        if not m:
            continue
        name = m.group("rule") if "rule" in regex.groupindex else m.group("code")
        rule = index.get(name)
        out.append(
            Diag(
                m.group("path"),
                int(m.group("line")),
                int(m.group("col")),
                rule.id if rule else prefix + name,
                rule.severity if rule else "SHOULD",
                m.group("msg"),
            )
        )
    return out
