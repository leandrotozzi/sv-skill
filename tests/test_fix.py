import shutil
from pathlib import Path

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from svstyle.checks import run_checks
from svstyle.fix import InvariantError, fix_text, token_signature
from svstyle.parse import ParseError
from svstyle.rules import load_rules

BASE = "`ifdef A\n  logic x;\n`endif\nmodule m;\nendmodule\n"


def test_signature_ignores_whitespace_and_comments():
    edited = "`ifdef A\n    logic   x;  // new\n`endif\n// Top.\nmodule m; endmodule"
    assert token_signature(edited) == token_signature(BASE)


def test_signature_sees_token_change():
    assert token_signature(BASE.replace("module m", "module n")) != token_signature(BASE)


def test_signature_sees_ifdef_disabled_text():
    assert token_signature(BASE.replace("logic x", "logic y")) != token_signature(BASE)


def test_signature_sees_directive_change():
    assert token_signature(BASE.replace("`ifdef A", "`ifndef A")) != token_signature(BASE)


# --- the fix pipeline -------------------------------------------------------------


RULES = load_rules()
FIX = Path(__file__).parent / "fixtures"
INPUTS = sorted((FIX / "input").glob("*.sv"))
needs_verible = pytest.mark.skipif(
    not shutil.which("verible-verilog-format"), reason="verible not installed"
)


@needs_verible
@pytest.mark.parametrize("src", INPUTS, ids=lambda p: p.name)
def test_golden(src):
    assert fix_text(src.read_text(), src.name, RULES) == (FIX / "expected" / src.name).read_text()


@needs_verible
@pytest.mark.parametrize("src", INPUTS, ids=lambda p: p.name)
def test_idempotent(src):
    once = fix_text(src.read_text(), src.name, RULES)
    assert fix_text(once, src.name, RULES) == once


@needs_verible
def test_clean_file_is_untouched():
    text = (FIX / "input" / "clean.sv").read_text()
    assert fix_text(text, "reg_byte.sv", RULES) == text


@needs_verible
def test_fixed_file_has_no_fixable_findings_left():
    src = FIX / "input" / "kitchen_sink.sv"
    out = fix_text(src.read_text(), src.name, RULES)
    assert [d for d in run_checks(out, src.name, RULES) if d.fix] == []


@needs_verible
def test_bare_module_gets_header_then_nettype_in_order():
    out = fix_text("module m;\nendmodule\n", "m.sv", RULES)
    assert out.index("// Copyright") < out.index("`default_nettype none") < out.index("module")
    assert out.rstrip().endswith("`resetall")


@needs_verible
def test_parse_error_is_refused():
    with pytest.raises(ParseError):
        fix_text("module m; logic ; endmodule\n", "m.sv", RULES)


@needs_verible
def test_invariant_catches_a_token_change(monkeypatch):
    import svstyle.fix as fx

    monkeypatch.setattr(fx, "verible_format", lambda t: t.replace("endmodule", "endmodule ; "))
    with pytest.raises(InvariantError):
        fix_text("module m;\nendmodule\n", "m.sv", RULES)


CLEAN = (FIX / "input" / "clean.sv").read_text()
COMMENTED = [i for i, ln in enumerate(CLEAN.splitlines(keepends=True)) if "// " in ln and i > 5]


@needs_verible
@settings(max_examples=25, deadline=None)
@given(st.sets(st.sampled_from(COMMENTED)))
def test_stripping_any_comments_is_repaired(strip):
    lines = CLEAN.splitlines(keepends=True)
    for i in strip:
        code, _, _ = lines[i].partition("//")
        lines[i] = code.rstrip() + "\n" if code.strip() else ""
    out = fix_text("".join(lines), "reg_byte.sv", RULES)
    assert [d for d in run_checks(out, "reg_byte.sv", RULES) if d.fix] == []
    assert fix_text(out, "reg_byte.sv", RULES) == out
