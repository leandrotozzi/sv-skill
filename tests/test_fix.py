import re
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


# Messy layouts fix must also settle in one pass: retabbed, two-space, trailing
# blanks, alignment squashed, comments stripped (so fix writes its TODOs).
MESS = {
    "as-is": lambda t: t,
    "tabs": lambda t: re.sub(r"^((?:    )+)", lambda m: "\t" * (len(m[1]) // 4), t, flags=re.M),
    "two": lambda t: re.sub(r"^((?:    )+)", lambda m: "  " * (len(m[1]) // 4), t, flags=re.M),
    "trail": lambda t: t.replace("\n", "   \n").rstrip("\n "),
    "squash": lambda t: re.sub(r" {2,}(?=\S)", " ", t),
    "nocmt": lambda t: re.sub(r" *//(?! svstyle).*$", "", t, flags=re.M),
}


@needs_verible
@pytest.mark.parametrize("mess", MESS)
@pytest.mark.parametrize("src", INPUTS, ids=lambda p: p.name)
def test_idempotent(src, mess):
    once = fix_text(MESS[mess](src.read_text()), src.name, RULES)
    assert fix_text(once, src.name, RULES) == once


@needs_verible
def test_clean_file_is_untouched():
    text = (FIX / "input" / "clean.sv").read_text()
    assert fix_text(text, "reg_byte.sv", RULES) == text


@needs_verible
def test_comment_above_a_short_declaration_moves_to_its_end():
    # A one-line comment written above a declaration that fits is moved, not
    # answered with a TODO: the author already wrote it.
    clean = (FIX / "input" / "clean.sv").read_text()
    decl = "    logic [Width-1:0] q_q;  // First-stage register\n"
    assert clean.count(decl) == 1
    text = clean.replace(decl, "    // First-stage register\n    logic [Width-1:0] q_q;\n")
    assert fix_text(text, "reg_byte.sv", RULES) == clean
    # A block of comment lines describes more than the line below: left alone.
    block = "    // Stage one.\n    // First-stage register\n    logic [Width-1:0] q_q;\n"
    text = clean.replace(decl, block)
    assert "TODO: describe" in fix_text(text, "reg_byte.sv", RULES)


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


# --- token-rewriting fixes (legacy code) -------------------------------------------

from svstyle.fix import allowed_edit  # noqa: E402


@pytest.mark.parametrize(
    "old,new,ok",
    [
        (["reg"], ["logic"], True),
        (["always", "@", "(", "*", ")"], ["always_comb"], True),
        (["always", "@", "*"], ["always_comb"], True),
        (["always"], ["always_ff"], True),
        (["x", "=", "1", ";"], ["begin", "x", "=", "1", ";", "end"], True),
        (["generate"], [], True),
        ([], ["automatic"], True),
        (["end"], ["end", "end"], True),
        (["a"], ["b"], False),
        (["logic"], ["reg"], False),  # the whitelist is directional
        (["begin"], [], False),  # never removes structure
    ],
)
def test_allowed_edit(old, new, ok):
    assert allowed_edit(old, new) is ok


LEGACY = """\
module legacy (
    input wire clk_i,
    input wire rst_ni,
    input wire [1:0] sel_i,
    input wire a_i,
    inout wire pad_io,
    output reg q_o,
    output wire y_o
);
    wire t = a_i & sel_i[0];
    reg c;
    always @(*) begin
        if (sel_i == 2'b00) c = a_i;
        else c = t;
    end
    always @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) q_o <= 1'b0;
        else q_o <= c;
`ifdef FOO
    assign y_o = c;
`else
    assign y_o = t;
`endif
    function logic inv(input logic x);
        return ~x;
    endfunction
    logic [1:0] g;
    generate
        for (genvar i = 0; i < 2; i++) begin : gen_g
            assign g[i] = inv(a_i);
        end
    endgenerate
endmodule
"""


def _toks(text):
    return token_signature(text)


@needs_verible
def test_legacy_code_is_modernised():
    out = fix_text(LEGACY, "legacy.sv", RULES)
    toks = _toks(out)
    assert "reg" not in toks and "generate" not in toks and "endgenerate" not in toks
    assert "always_comb" in toks and "always_ff" in toks and "always" not in toks
    assert "input  logic       clk_i" in out
    assert "wire  t = a_i & sel_i[0];" in out  # an initialiser on a wire is an assign: kept
    assert "// TODO: describe\n    always_comb begin" in out  # DOC-005 sees the new block
    assert "inout  wire        pad_io" in out  # an inout is a net: kept
    assert "if (!rst_ni) begin" in out and "end else begin" in out
    assert "if (sel_i == 2'b00) begin" in out
    assert "`endif  // FOO" in out
    assert "function automatic logic inv" in out
    assert fix_text(out, "legacy.sv", RULES) == out


@needs_verible
def test_clocked_always_with_blocking_assignments_stays_always():
    text = (
        "module m (\n    input logic clk_i,\n    input logic a_i,\n    output logic b_o\n);\n"
        "    logic t;\n    always @(posedge clk_i) begin\n        t = a_i;\n        b_o <= t;\n"
        "    end\nendmodule\n"
    )
    out = fix_text(text, "m.sv", RULES)
    assert "always_ff" not in _toks(out)
    assert ("LNG-002", False) in {(d.rule, d.fixable) for d in run_checks(out, "m.sv", RULES)}


@needs_verible
def test_typed_wire_drops_the_wire():
    # Verible cannot parse `wire logic`, so `fix` cuts the `wire` before formatting.
    text = (
        "module m (\n    input wire logic a_i,  // A.\n    output logic b_o  // B.\n);\n"
        "    wire logic [1:0] t;  // T.\n    assign t = {a_i, a_i};\n    assign b_o = t[0];\n"
        "endmodule\n"
    )
    out = fix_text(text, "m.sv", RULES)
    assert "wire" not in _toks(out)
    assert "input  logic a_i" in out and "logic [1:0] t;" in out
    assert fix_text(out, "m.sv", RULES) == out


@needs_verible
def test_explicit_sensitivity_list_is_reported_not_rewritten():
    text = (
        "module m (\n    input logic a_i,\n    input logic b_i,\n    output logic y_o\n);\n"
        "    always @(a_i) begin\n        y_o = a_i & b_i;\n    end\nendmodule\n"
    )
    out = fix_text(text, "m.sv", RULES)
    assert "always_comb" not in _toks(out)  # would change what simulation does
    assert "LNG-003" in {d.rule for d in run_checks(out, "m.sv", RULES)}


@needs_verible
def test_else_if_chain_is_not_wrapped():
    text = (
        "module m (\n    input logic a_i,\n    input logic b_i,\n    output logic y_o\n);\n"
        "    always_comb begin\n        if (a_i) y_o = 1'b1;\n        else if (b_i) y_o = 1'b0;\n"
        "        else y_o = 1'b1;\n    end\nendmodule\n"
    )
    out = fix_text(text, "m.sv", RULES)
    assert "end else if (b_i) begin" in out and out.count("begin") == 4


@needs_verible
def test_invariant_rejects_an_edit_off_the_whitelist(monkeypatch):
    import svstyle.fix as fx

    monkeypatch.setattr(fx, "verible_format", lambda t: t.replace("logic", "bit"))
    with pytest.raises(InvariantError):
        fix_text("module m;\n    logic x;  // X\nendmodule\n", "m.sv", RULES)


@needs_verible
@pytest.mark.skipif(not shutil.which("yosys"), reason="yosys not installed")
@pytest.mark.parametrize("define", ["", "-DFOO"], ids=["no-define", "FOO"])
def test_legacy_rewrite_is_formally_equivalent(tmp_path, define):
    """Yosys proves the fixed module equal to the original, for both `ifdef branches."""
    import subprocess

    # Yosys reads neither `return` nor inout here; the rewrites under test are unaffected.
    src = LEGACY.replace("    inout wire pad_io,\n", "").replace("return ~x;", "inv = ~x;")
    (tmp_path / "gold.v").write_text(src)
    fixed = fix_text(src, "legacy.sv", RULES).replace("module legacy", "module gate_legacy")
    (tmp_path / "gate.sv").write_text(fixed)
    script = (
        f"read_verilog {define} -sv gold.v; read_verilog {define} -sv gate.sv; proc; async2sync; "
        "equiv_make legacy gate_legacy eq; hierarchy -top eq; "
        "equiv_simple -seq 5; equiv_induct -seq 5; equiv_status -assert"
    )
    res = subprocess.run(
        ["yosys", "-q", "-p", script], cwd=tmp_path, capture_output=True, text=True
    )
    assert res.returncode == 0, res.stdout + res.stderr
