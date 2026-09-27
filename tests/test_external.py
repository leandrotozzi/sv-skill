import shutil
from pathlib import Path

import pytest

from svstyle import external as ext
from svstyle.fix import token_signature
from svstyle.rules import load_rules

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
%Error: Exiting due to 1 error(s)
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
        ("ks.sv", 7, 9, "EXT-VLTR-DECLFILENAME", "SHOULD"),
        ("ks.sv", 55, 9, "EXT-VLTR-MODMISSING", "SHOULD"),
    ]


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
