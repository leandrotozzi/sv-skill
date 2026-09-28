import shutil
from pathlib import Path

import pytest

from svstyle import external as ext
from svstyle.fix import token_signature
from svstyle.rules import load_rules, tool_index

RULES = load_rules()
KS = Path(__file__).parent / "fixtures" / "input" / "kitchen_sink.sv"
needs_verible = pytest.mark.skipif(
    not shutil.which("verible-verilog-format"), reason="verible not installed"
)
needs_verilator = pytest.mark.skipif(not shutil.which("verilator"), reason="verilator missing")

# --- output parsing (no subprocess) -------------------------------------------

VERIBLE_LINT_OUT = """\
ks.sv:25:37-39: input port names must end with _i, _ni or _pi [Style: suffixes-for-signals-and-types] [port-name-suffix]
ks.sv:62:19-23: Use named ports for module instantiation with more than one port [Style: module-instantiation] [module-port]
ks.sv:3:1: something new [Style: x] [brand-new-rule]
"""  # noqa: E501

VERILATOR_OUT = """\
%Warning-LATCH: ks.sv:12:5: Latch inferred for signal 'm.q' (not all control paths of combinational always assign a value)
                       ... For warning description see https://verilator.org/warn/LATCH?v=5.052
%Warning-DECLFILENAME: ks.sv:7:9: Filename 'ks' does not match PACKAGE name: 'ks_pkg'
%Error-MODMISSING: ks.sv:55:9: Cannot find file containing module: 'ks_buf'
%Error: ks.sv:6:12: Signal definition not found, and implicit disabled with `default_nettype: 'b_ou'
%Error: Exiting due to 2 error(s)
"""  # noqa: E501


def _brief(diags):
    return [(d.path, d.line, d.col, d.rule, d.severity) for d in diags]


def test_parse_verible_lint_maps_rule_ids():
    assert _brief(ext.parse_verible_lint(VERIBLE_LINT_OUT, RULES)) == [
        ("ks.sv", 25, 37, "NAM-002", "MUST"),
        ("ks.sv", 62, 19, "PRT-005", "MUST"),
        ("ks.sv", 3, 1, "EXT-VL-brand-new-rule", "SHOULD"),
    ]


def test_parse_verible_lint_keeps_message_without_tags():
    (d, *_) = ext.parse_verible_lint(VERIBLE_LINT_OUT, RULES)
    assert d.message == "input port names must end with _i, _ni or _pi"


def test_parse_verilator_maps_codes_and_passes_unknown_through():
    assert _brief(ext.parse_verilator(VERILATOR_OUT, RULES)) == [
        ("ks.sv", 12, 5, "LNG-006", "MUST"),
        ("ks.sv", 7, 9, "STR-001", "MUST"),
        # A submodule outside the file list is expected when checking a subset.
        ("ks.sv", 55, 9, "EXT-VLTR-MODMISSING", "SHOULD"),
        # An error without a code is an elaboration failure: never dropped, never soft.
        ("ks.sv", 6, 12, "EXT-VLTR-ERROR", "MUST"),
    ]


def test_formatter_owned_lint_findings_are_fixable_except_what_it_cannot_wrap():
    out = "a.sv:1:1: tab [Style: x] [no-tabs]\na.sv:2:1: long [Style: x] [line-length]\n"
    assert [d.fixable for d in ext.parse_verible_lint(out, RULES)] == [True, False]


def test_every_verible_name_fix_resolves_belongs_to_an_autofix_rule():
    index = tool_index(RULES, "verible-lint")
    assert {n: index[n].autofix for n in ext.FIXED_BY_FIX} == dict.fromkeys(ext.FIXED_BY_FIX, True)


def test_parse_verible_lint_reports_its_own_syntax_errors():
    """pyslang already accepted the file, so this is Verible's parser, not the author's bug."""
    (d,) = ext.parse_verible_lint('vbad.sv:3:1-9: syntax error at token "endmodule"\n', RULES)
    assert (d.rule, d.severity, d.line) == ("EXT-VL-syntax", "SHOULD", 3)
    assert "not checked" in d.message


# --- real tools ---------------------------------------------------------------


@needs_verible
def test_verible_format_only_changes_whitespace():
    text = KS.read_text()
    out = ext.verible_format(text)
    assert out != text
    assert token_signature(out) == token_signature(text)
    assert "\n    logic [Width-1:0]" in out  # 4-space house indent


@needs_verible
def test_verible_format_raises_on_syntax_error():
    with pytest.raises(ext.ToolFailed):
        ext.verible_format("module m; logic ; endmodule\n")


@needs_verible
def test_verible_verify_flags_unformatted_file():
    (d,) = ext.verible_verify([str(KS)], RULES)
    assert (d.rule, d.fixable) == ("FMT-002", True)


@needs_verible
def test_verible_lint_runs_with_shipped_config():
    rules = {d.rule for d in ext.verible_lint([str(KS)], RULES)}
    assert {"NAM-002", "PRT-005"} <= rules


@needs_verilator
def test_verilator_lint_reports_latch(tmp_path):
    f = tmp_path / "m.sv"
    f.write_text(
        "module m (\n    input logic a_i,\n    output logic q_o\n);\n"
        "    always_comb begin\n        if (a_i) q_o = 1'b1;\n    end\nendmodule\n"
    )
    assert "LNG-006" in {d.rule for d in ext.verilator_lint([str(f)], RULES)}


@needs_verilator
def test_verilator_elaboration_error_is_a_must(tmp_path):
    f = tmp_path / "typo.sv"
    f.write_text(
        "`default_nettype none\nmodule typo (\n    input  logic a_i,\n    output logic b_o\n);\n"
        "    assign b_ou = a_i;\nendmodule\n`resetall\n"
    )
    assert ("EXT-VLTR-ERROR", "MUST", 6) in {
        (d.rule, d.severity, d.line) for d in ext.verilator_lint([str(f)], RULES)
    }


def test_verilator_failure_without_a_located_error_is_reported(tmp_path, monkeypatch):
    f = tmp_path / "m.sv"
    f.write_text("module m;\nendmodule\n")
    monkeypatch.setattr(ext, "_run", _fake_run(1, "%Error: Internal Error: something broke\n"))
    (d,) = ext.verilator_lint([str(f)], RULES)
    assert (d.path, d.rule, d.severity) == (str(f), "EXT-VLTR-ERROR", "MUST")
    assert "Internal Error" in d.message


@needs_verilator
def test_verilator_synthesis_warnings_map_to_house_rules(tmp_path):
    f = tmp_path / "bugs.sv"
    f.write_text(
        "module bugs (\n    input  logic [7:0] a_i,\n    input  logic [1:0] s_i,\n"
        "    output logic [3:0] n_o,\n    output logic l_o,\n    output logic c_o,\n"
        "    output logic u_o\n);\n    logic und, spare;\n    assign n_o = a_i;\n"
        "    assign l_o = und;\n    always_comb begin\n        c_o = 1'b0;\n"
        "        case (s_i)\n            2'b00: c_o = 1'b1;\n            2'b01: c_o = 1'b0;\n"
        "        endcase\n    end\n    always_comb begin\n        casex (s_i)\n"
        "            2'b1x: u_o = 1'b1;\n            default: u_o = a_i[9];\n        endcase\n"
        "    end\n    sub u_sub (.a_i(a_i[0]), .o_o());\nendmodule\n"
        "module sub (input logic a_i, input logic b_i, output logic o_o);\n"
        "    assign o_o = a_i & b_i;\nendmodule\n"
    )
    rules = {d.rule for d in ext.verilator_lint([str(f)], RULES)}
    assert {"PRT-004", "STR-001", "LNG-015", "LNG-016", "LNG-017", "LNG-007", "LNG-009"} <= rules
    assert not {r for r in rules if r.startswith("EXT-")}, rules  # `.o_o()` is PRT-004's no-connect


def test_missing_tool_raises(monkeypatch):
    monkeypatch.setattr(ext.shutil, "which", lambda _: None)
    with pytest.raises(ext.ToolMissing, match="verible-verilog-format"):
        ext.verible_format("module m; endmodule\n")


@needs_verible
def test_installed_verible_matches_pin():
    assert ext.verible_version() == ext.KNOWN_GOOD_VERIBLE_VERSION


@needs_verible
def test_nam006_allows_all_caps_only_for_localparams(tmp_path):
    f = tmp_path / "m.sv"
    f.write_text(
        "module m #(\n    parameter int unsigned Depth = 4,  // Tunable\n"
        "    parameter int unsigned MAX_DEPTH = 8  // Tunable, wrongly ALL_CAPS\n) ();\n"
        "    localparam int unsigned DepthW = $clog2(Depth);  // Derived\n"
        "    localparam logic [7:0] SOF_BYTE = 8'h7E;  // Protocol constant\nendmodule\n"
    )
    lines = {d.line for d in ext.verible_lint([str(f)], RULES) if d.rule == "NAM-006"}
    assert lines == {3}


@needs_verilator
def test_verilator_reports_only_the_files_asked_for(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)  # Verilator finds sub.sv in the working directory
    (tmp_path / "sub.sv").write_text(
        "module sub (\n    input logic a_i,\n    output logic b_o\n);\n    logic spare;\n"
        "    assign b_o = a_i;\nendmodule\n"
    )
    top = tmp_path / "top.sv"
    top.write_text(
        "module top (\n    input logic a_i,\n    output logic b_o\n);\n"
        "    sub u_sub (\n        .a_i(a_i),\n        .b_o(b_o)\n    );\nendmodule\n"
    )
    assert [d.path for d in ext.verilator_lint(["top.sv"], RULES)] == []


@needs_verible
@pytest.mark.parametrize(
    "block",
    [
        # Memory write: an indexed array element is not a _q/_d pair.
        "always_ff @(posedge clk_i) begin\n        if (we_i) begin\n"
        "            regs_q[waddr_i] <= wdata_i;\n        end\n    end",
        # Per-domain reset in a CDC module (lowRISC prim_pulse_sync naming).
        "always_ff @(posedge clk_i or negedge rst_src_ni) begin\n"
        "        if (!rst_src_ni) begin\n            tog_q <= 1'b0;\n"
        "        end else begin\n            tog_q <= tog_d;\n        end\n    end",
    ],
    ids=["memory-write", "domain-reset"],
)
def test_nam004_accepts_memories_and_domain_resets(tmp_path, block):
    f = tmp_path / "m.sv"
    f.write_text(
        "module m (\n    input logic clk_i,\n    input logic rst_src_ni,\n    input logic we_i,\n"
        "    input logic [1:0] waddr_i,\n    input logic [7:0] wdata_i\n);\n"
        "    logic [7:0] regs_q[4];\n    logic tog_q, tog_d;\n    assign tog_d = ~tog_q;\n"
        f"    {block}\nendmodule\n"
    )
    assert [d for d in ext.verible_lint([str(f)], RULES) if d.rule == "NAM-004"] == []


def _fake_run(returncode, stderr):
    import subprocess

    return lambda *a, **k: subprocess.CompletedProcess([], returncode, "", stderr)


def test_verify_reports_non_convergent_formatting(monkeypatch):
    monkeypatch.setattr(ext, "_run", _fake_run(0, "x.sv: formatting failed to converge! ..."))
    (d,) = ext.verible_verify(["x.sv"], RULES)
    assert (d.rule, d.fixable) == ("FMT-002", False)
    assert "converge" in d.message


def test_format_failure_message_is_short(monkeypatch):
    dump = "x.sv: formatting failed to converge! Please file a bug.\n" + "code line\n" * 4000
    monkeypatch.setattr(ext, "_run", _fake_run(0, dump))
    with pytest.raises(ext.ToolFailed) as exc:
        ext.verible_format("module m; endmodule\n")
    assert len(str(exc.value)) < 300 and "converge" in str(exc.value)


def test_ci_pins_the_same_verible_as_the_code():
    ci = (Path(__file__).parents[1] / ".github" / "workflows" / "ci.yml").read_text()
    assert f"VERIBLE: {ext.KNOWN_GOOD_VERIBLE_VERSION}" in ci


@needs_verilator
def test_package_constants_are_not_unused_when_linted_alone(tmp_path):
    pkg = tmp_path / "cfg_pkg.sv"
    pkg.write_text(
        "package cfg_pkg;\n    localparam int unsigned Depth = 4;  // Entries\nendpackage\n"
    )
    mod = tmp_path / "m.sv"
    mod.write_text(
        "module m #(\n    parameter int unsigned Spare = 1  // Unused on purpose\n) (\n"
        "    input logic a_i,\n    output logic b_o\n);\n    assign b_o = a_i;\nendmodule\n"
    )
    rules = [(Path(d.path).name, d.rule) for d in ext.verilator_lint([str(pkg), str(mod)], RULES)]
    assert ("cfg_pkg.sv", "EXT-VLTR-UNUSEDPARAM") not in rules
    assert ("m.sv", "EXT-VLTR-UNUSEDPARAM") in rules  # a module's unused parameter still counts


# --- Yosys: check --synth ---------------------------------------------------------

needs_yosys = pytest.mark.skipif(not shutil.which("yosys"), reason="yosys missing")

YOSYS_OUT = """\
Warning: found logic loop in module loop:
    cell $xor$loop.sv:7$1 ($xor) source: loop.sv:7.16-7.23
      A[0] --> Y[0]
Warning: multiple conflicting drivers for loop.\\z_o:
    port Y[0] of cell $and$loop.sv:11$2 ($and) source: loop.sv:11.12-11.20
Warning: Wire loop.\\u is used but has no driver.
Warning: something new
"""


def test_parse_yosys_maps_and_locates(tmp_path):
    assert _brief(ext.parse_yosys(YOSYS_OUT, RULES, "loop.sv")) == [
        ("loop.sv", 7, 16, "SYN-005", "MUST"),
        ("loop.sv", 11, 12, "LNG-005", "MUST"),
        ("loop.sv", 1, 1, "LNG-016", "MUST"),
        ("loop.sv", 1, 1, "EXT-YOSYS-warning", "SHOULD"),
    ]


def test_parse_yosys_read_error_is_a_should():
    """Yosys reads less SystemVerilog than slang: its refusal is not the author's bug."""
    (d,) = ext.parse_yosys("gold.v:24: ERROR: syntax error, unexpected '~'\n", RULES, "gold.v")
    assert (d.path, d.line, d.rule, d.severity) == ("gold.v", 24, "EXT-YOSYS-read", "SHOULD")
    assert "not checked" in d.message


@needs_yosys
def test_yosys_finds_a_combinational_loop(tmp_path):
    f = tmp_path / "loop.sv"
    f.write_text(
        "module loop (\n    input  logic a_i,\n    output logic y_o\n);\n    logic x, y;\n"
        "    assign x = y ^ a_i;\n    assign y = x;\n    assign y_o = y;\nendmodule\n"
    )
    assert ("SYN-005", 6) in {(d.rule, d.line) for d in ext.yosys_check([str(f)], RULES)}


@needs_yosys
def test_yosys_passes_the_templates():
    assets = Path(__file__).parents[1] / "skill" / "systemverilog-rtl" / "assets"
    files = [str(assets / "fsm_pkg.sv"), str(assets / "fsm.sv"), str(assets / "skeleton.sv")]
    assert ext.yosys_check(files, RULES, [str(assets)]) == []
