"""The skill's templates are what a model copies: they must pass the full check as-is."""

import json
import shutil
from pathlib import Path

import pytest

from svstyle.checks import PLACEHOLDER
from svstyle.cli import main
from svstyle.fix import fix_text
from svstyle.rules import load_rules

ASSETS = Path(__file__).parents[1] / "skill" / "systemverilog-rtl" / "assets"
TEMPLATES = sorted(ASSETS.glob("*.sv"))
needs_tools = pytest.mark.skipif(
    not (shutil.which("verible-verilog-format") and shutil.which("verilator")),
    reason="verible or verilator missing",
)


def test_there_are_templates():
    assert {p.name for p in TEMPLATES} == {"skeleton.sv", "fsm.sv", "fsm_pkg.sv"}


@needs_tools
@pytest.mark.parametrize("src", TEMPLATES, ids=lambda p: p.name)
def test_template_is_a_fix_fixed_point(src):
    assert fix_text(src.read_text(), src.name, load_rules()) == src.read_text()


@needs_tools
def test_templates_pass_full_check_with_only_the_company_placeholder(capsys):
    code = main(["check", "--json", *map(str, TEMPLATES)])
    doc = json.loads(capsys.readouterr().out)
    assert code == 0
    assert {(d["rule"], d["severity"]) for d in doc["diagnostics"]} == {("DOC-001", "SHOULD")}
    assert all(PLACEHOLDER in d["message"] for d in doc["diagnostics"])
