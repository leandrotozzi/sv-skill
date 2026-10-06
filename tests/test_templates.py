"""The skill's templates are what a model copies: they must pass the full check as-is."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from svstyle.checks import PLACEHOLDER
from svstyle.cli import main
from svstyle.fix import fix_text
from svstyle.rules import load_rules

ASSETS = Path(__file__).parents[1] / "skill" / "systemverilog-rtl" / "assets"
TEMPLATES = sorted([*ASSETS.glob("*.sv"), *ASSETS.glob("*.svh")])
RTL = sorted(ASSETS.glob("*.sv"), key=lambda p: (not p.name.endswith("_pkg.sv"), p.name))
needs_tools = pytest.mark.skipif(
    not (shutil.which("verible-verilog-format") and shutil.which("verilator")),
    reason="verible or verilator missing",
)


def test_there_are_templates():
    assert {p.name for p in TEMPLATES} == {
        "skeleton.sv", "fsm.sv", "fsm_pkg.sv", "sync_ff.sv", "assert_macros.svh"
    }  # fmt: skip


@pytest.mark.parametrize("name", ["skeleton.sv", "fsm.sv"])
def test_modules_check_their_outputs_are_known(name):
    text = (ASSETS / name).read_text()
    assert '`include "assert_macros.svh"' in text and "`ASSERT_KNOWN(" in text


@needs_tools
def test_templates_lint_clean_with_assertions_enabled():
    res = subprocess.run(
        ["verilator", "--lint-only", "-Wall", "--assert", "-Wno-MULTITOP", *map(str, RTL)],
        cwd=ASSETS, capture_output=True, text=True,
    )  # fmt: skip
    assert res.returncode == 0, res.stderr


@pytest.mark.skipif(not shutil.which("yosys"), reason="yosys missing")
def test_templates_synthesize_with_assertions_compiled_out():
    for top in ("skeleton", "fsm"):
        files = " ".join(p.name for p in RTL)
        res = subprocess.run(
            ["yosys", "-q", "-p", f"read_verilog -sv {files}; synth -top {top}"],
            cwd=ASSETS, capture_output=True, text=True,
        )  # fmt: skip
        assert res.returncode == 0, res.stderr


@needs_tools
@pytest.mark.parametrize("src", TEMPLATES, ids=lambda p: p.name)
def test_template_is_a_fix_fixed_point(src):
    assert fix_text(src.read_text(), str(src), load_rules()) == src.read_text()


@needs_tools
def test_templates_pass_full_check_with_only_the_company_placeholder(capsys):
    code = main(["check", "--json", *map(str, TEMPLATES)])
    doc = json.loads(capsys.readouterr().out)
    assert code == 0
    assert {(d["rule"], d["severity"]) for d in doc["diagnostics"]} == {("DOC-001", "SHOULD")}
    assert all(PLACEHOLDER in d["message"] for d in doc["diagnostics"])
