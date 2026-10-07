import json
import shutil
from pathlib import Path

import pytest

from svstyle import external
from svstyle.cli import main

FIX = Path(__file__).parent / "fixtures" / "input"
CLEAN = (FIX / "clean.sv").read_text()
needs_verible = pytest.mark.skipif(
    not shutil.which("verible-verilog-format"), reason="verible not installed"
)


@pytest.fixture
def sv(tmp_path):
    def make(text=CLEAN, name="reg_byte.sv"):
        p = tmp_path / name
        p.write_text(text)
        return p

    return make


def _run(capsys, *argv):
    code = main(list(map(str, argv)))
    out, err = capsys.readouterr()
    return code, out, err


# --- check ----------------------------------------------------------------------


def test_check_clean_exits_0(capsys, sv):
    code, out, _ = _run(capsys, "check", "--no-external", sv())
    assert code == 0
    assert out.strip().endswith("0 findings")


def test_check_reports_must_violation_as_text(capsys, sv):
    p = sv(CLEAN.replace("rst_ni,  // Asynchronous reset, active-low", "rst_ni,"))
    code, out, _ = _run(capsys, "check", "--no-external", p)
    assert code == 1
    assert f"{p}:14:1: DOC-003 `rst_ni` has no trailing // comment [fix available]" in out


def test_check_should_only_exits_0(capsys, sv):
    p = sv(CLEAN.replace("ACME Corp", "<Company>"))
    code, out, _ = _run(capsys, "check", "--no-external", p)
    assert code == 0
    assert "DOC-001" in out


def test_check_json_envelope(capsys, sv):
    p = sv(CLEAN.replace("  // First-stage register", ""))
    code, out, _ = _run(capsys, "check", "--no-external", "--json", p)
    doc = json.loads(out)
    assert (code, doc["ok"], doc["exit_code"], doc["kind"]) == (1, False, 1, "violations")
    assert doc["summary"] == {"MUST": 1, "SHOULD": 0, "MAY": 0}
    (d,) = doc["diagnostics"]
    assert (d["path"], d["line"], d["rule"], d["fixable"]) == (str(p), 18, "DOC-004", True)


def test_check_select_and_ignore(capsys, sv):
    p = sv(
        CLEAN.replace("  // First-stage register", "").replace("    // Capture the payload.\n", "")
    )

    def rules(*argv):
        out = _run(capsys, "check", "--no-external", "--json", *argv, p)[1]
        return {d["rule"] for d in json.loads(out)["diagnostics"]}

    assert rules() == {"DOC-004", "DOC-005"}
    assert rules("--select", "DOC-004") == {"DOC-004"}
    assert rules("--ignore", "DOC-00") == set()
    assert rules("--select", "DOC", "--ignore", "DOC-005") == {"DOC-004"}


def test_check_parse_error_is_refused(capsys, sv):
    p = sv("module m; logic ; endmodule\n")
    code, out, _ = _run(capsys, "check", "--no-external", "--json", p)
    doc = json.loads(out)
    assert (code, doc["kind"]) == (3, "refused")
    assert "expected a declaration name" in doc["error"]


def test_check_missing_file_exits_2(capsys, tmp_path):
    code, _, err = _run(capsys, "check", "--no-external", tmp_path / "nope.sv")
    assert code == 2 and "nope.sv" in err


def test_check_skips_missing_external_tools_with_warning(capsys, sv, monkeypatch):
    monkeypatch.setattr(external.shutil, "which", lambda _: None)
    code, _, err = _run(capsys, "check", sv())
    assert code == 0 and "not found" in err


@needs_verible
def test_check_runs_external_tools(capsys):
    code, out, _ = _run(capsys, "check", "--json", FIX / "kitchen_sink.sv")
    rules = {d["rule"] for d in json.loads(out)["diagnostics"]}
    assert code == 1 and {"NAM-002", "FMT-002", "DOC-003"} <= rules


@needs_verible
def test_waiver_covers_external_tool_findings(capsys, sv):
    text = CLEAN.replace(
        "    logic [Width-1:0] q_q;  // First-stage register",
        "    // svstyle: waive NAM-001 name fixed by the vendor netlist\n"
        "    logic [Width-1:0] q_q, vendorQ;  // First-stage register",
    )
    rules = {
        d["rule"] for d in json.loads(_run(capsys, "check", "--json", sv(text))[1])["diagnostics"]
    }
    assert "NAM-001" not in rules
    rules = {
        d["rule"]
        for d in json.loads(
            _run(capsys, "check", "--json", sv(text.replace("waive NAM-001", "x")))[1]
        )["diagnostics"]
    }
    assert "NAM-001" in rules  # the same file without the waiver does report it


# --- fix ------------------------------------------------------------------------


@needs_verible
def test_fix_writes_file_and_leaves_only_its_todo(capsys, sv):
    p = sv(CLEAN.replace("rst_ni,  // Asynchronous reset, active-low", "rst_ni,"))
    code, out, _ = _run(capsys, "fix", p)
    assert "fixed 1 file" in out
    assert "rst_ni,  // TODO: describe" in p.read_text()
    # The placeholder is for the author to fill in: check keeps failing until then.
    code, out, _ = _run(capsys, "check", "--no-external", p)
    assert code == 1 and "1 findings" in out and "placeholder" in out
    p.write_text(p.read_text().replace("TODO: describe", "Asynchronous reset, active-low"))
    assert _run(capsys, "check", "--no-external", p)[0] == 0


@needs_verible
def test_fix_diff_does_not_write(capsys, sv):
    text = CLEAN.replace("rst_ni,  // Asynchronous reset, active-low", "rst_ni,")
    p = sv(text)
    code, out, _ = _run(capsys, "fix", "--diff", p)
    # Non-zero when a file would change, so `fix --diff` gates CI like `ruff format --diff`.
    assert code == 1 and "+    input  logic             rst_ni,  // TODO: describe" in out
    assert p.read_text() == text


@needs_verible
def test_fix_reports_what_it_cannot_fix(capsys, sv):
    p = sv(CLEAN.replace("u_out (", "u_out (.*);\n    wire unused_w;  // x\n    prim_flop u_x ("))
    code, out, _ = _run(capsys, "fix", "--json", p)
    doc = json.loads(out)
    assert code == 1 and "PRT-003" in {d["rule"] for d in doc["diagnostics"]}


def test_fix_refuses_without_verible(capsys, sv, monkeypatch):
    monkeypatch.setattr(external.shutil, "which", lambda _: None)
    code, _, err = _run(capsys, "fix", sv())
    assert code == 2 and "verible-verilog-format" in err


def test_fix_invariant_breach_exits_4(capsys, sv, monkeypatch):
    import svstyle.fix as fx

    monkeypatch.setattr(fx, "verible_format", lambda t: t.replace("endmodule", "endmodule ;"))
    p = sv()
    code, _, err = _run(capsys, "fix", p)
    assert code == 4 and "fix changed tokens" in err
    assert p.read_text() == CLEAN


def test_check_and_fix_take_include_dirs(capsys, tmp_path):
    inc = tmp_path / "inc"
    inc.mkdir()
    (inc / "defs.svh").write_text("`define WIDTH 8\n")
    p = tmp_path / "reg_byte.sv"
    p.write_text(
        CLEAN.replace("`default_nettype none\n", '`default_nettype none\n`include "defs.svh"\n')
    )
    assert _run(capsys, "check", "--no-external", p)[0] == 3
    assert _run(capsys, "check", "--no-external", "-I", inc, p)[0] == 0


@needs_verible
def test_fix_fills_company_from_config(capsys, tmp_path):
    (tmp_path / ".svstyle.toml").write_text('company = "Foo Inc"\n')
    p = tmp_path / "reg_byte.sv"
    p.write_text(CLEAN.replace("ACME Corp", "<Company>"))
    assert _run(capsys, "fix", p)[0] == 0
    assert p.read_text() == CLEAN.replace("ACME Corp", "Foo Inc")
    code, out, _ = _run(capsys, "check", "--no-external", p)
    assert code == 0 and out.strip().endswith("0 findings")


def test_bad_config_exits_2(capsys, tmp_path):
    (tmp_path / ".svstyle.toml").write_text("company = 3\n")
    p = tmp_path / "reg_byte.sv"
    p.write_text(CLEAN)
    code, _, err = _run(capsys, "check", "--no-external", p)
    assert code == 2 and ".svstyle.toml" in err


@needs_verible
def test_fix_diff_on_a_clean_file_exits_0(capsys, sv):
    assert _run(capsys, "fix", "--diff", sv())[0] == 0


# --- inputs: directories and filelists ------------------------------------------


def test_a_directory_expands_to_its_sv_files(capsys, tmp_path):
    (tmp_path / "rtl" / "sub").mkdir(parents=True)
    (tmp_path / "rtl" / "sub" / "reg_byte.sv").write_text(CLEAN)
    (tmp_path / "rtl" / "notes.txt").write_text("not RTL")
    code, out, _ = _run(capsys, "check", "--no-external", "--json", tmp_path / "rtl")
    assert code == 0 and json.loads(out)["ok"]


def test_filelist_brings_files_incdirs_and_nested_lists(capsys, tmp_path):
    inc = tmp_path / "inc"
    inc.mkdir()
    (inc / "defs.svh").write_text("`define WIDTH 8\n")
    (tmp_path / "reg_byte.sv").write_text(
        CLEAN.replace("`default_nettype none\n", '`default_nettype none\n`include "defs.svh"\n')
    )
    (tmp_path / "inner.f").write_text("// nested list\nreg_byte.sv\n")
    # -F: paths inside are relative to the list, as in Verilator and VCS.
    (tmp_path / "top.f").write_text("+incdir+$INC_DIR\n-F inner.f\n+define+X=1\n")
    import os

    os.environ["INC_DIR"] = str(inc)
    try:
        code, out, err = _run(capsys, "check", "--no-external", "-F", tmp_path / "top.f")
    finally:
        del os.environ["INC_DIR"]
    assert code == 0, err
    assert out.strip().endswith("0 findings")


def test_no_inputs_is_an_error(capsys):
    with pytest.raises(SystemExit):
        main(["check"])


# --- .svstyle.toml: select / ignore / include -------------------------------------


def test_config_select_ignore_and_include(capsys, tmp_path):
    (tmp_path / "inc").mkdir()
    (tmp_path / "inc" / "defs.svh").write_text("`define WIDTH 8\n")
    (tmp_path / ".svstyle.toml").write_text('ignore = ["DOC-003"]\ninclude = ["inc"]\n')
    p = tmp_path / "reg_byte.sv"
    p.write_text(
        CLEAN.replace("rst_ni,  // Asynchronous reset, active-low", "rst_ni,").replace(
            "`default_nettype none\n", '`default_nettype none\n`include "defs.svh"\n'
        )
    )
    code, out, _ = _run(capsys, "check", "--no-external", p)
    assert code == 0 and out.strip().endswith("0 findings")  # include resolved, DOC-003 ignored
    code, out, _ = _run(capsys, "check", "--no-external", "--select", "DOC", p)
    assert code == 1  # a CLI flag overrides the file


@pytest.mark.skipif(not shutil.which("yosys"), reason="yosys missing")
def test_check_synth_reports_a_combinational_loop(capsys, tmp_path):
    p = tmp_path / "loop.sv"
    p.write_text(
        "module loop (\n    input  logic a_i,\n    output logic y_o\n);\n    logic x, y;\n"
        "    assign x = y ^ a_i;\n    assign y = x;\n    assign y_o = y;\nendmodule\n"
    )
    rules = lambda *argv: {  # noqa: E731
        d["rule"] for d in json.loads(_run(capsys, "check", "--json", *argv, p)[1])["diagnostics"]
    }
    assert "SYN-005" not in rules()  # opt-in: synthesis is the slow part
    assert "SYN-005" in rules("--synth")
    # A project that synthesises with Yosys says so once, in its config.
    (tmp_path / ".svstyle.toml").write_text('synth = "yosys"\n')
    assert "SYN-005" in rules()
    (tmp_path / ".svstyle.toml").write_text('synth = "vivado"\n')
    assert "SYN-005" not in rules()


def test_non_utf8_file_is_an_error_not_a_crash(capsys, tmp_path):
    p = tmp_path / "bad.sv"
    p.write_bytes(b"\xff module x; endmodule\n")
    code, _, err = _run(capsys, "check", "--no-external", p)
    assert code == 2 and "UTF-8" in err


def test_rules_gen_and_check_refuse_outside_the_repo(capsys, monkeypatch, tmp_path):
    from svstyle import cli

    monkeypatch.setattr(cli, "SKILL_MD", tmp_path / "SKILL.md")  # as in an installed wheel
    for flag in ("--gen", "--check"):
        code, _, err = _run(capsys, "rules", flag)
        assert code == 2 and "checkout" in err


@needs_verible
def test_fix_sees_inouts_in_the_other_files(capsys, tmp_path):
    (tmp_path / "pad.sv").write_text("module pad (\n    inout wire io_io  // Pad.\n);\nendmodule\n")
    top = tmp_path / "top.sv"
    top.write_text("module top;\n    wire a;  // A.\n    pad u_pad (.io_io(a));\nendmodule\n")
    _run(capsys, "fix", tmp_path / "pad.sv", top)
    assert "wire a;" in top.read_text()


@pytest.mark.skipif(not shutil.which("yosys"), reason="yosys missing")
def test_undriven_output_of_a_missing_module_is_a_should(capsys, tmp_path):
    p = tmp_path / "top.sv"
    p.write_text(
        "module top (\n    input  logic a_i,\n    output logic b_o\n);\n"
        "    sub u_sub (.a_i(a_i), .b_o(b_o));\nendmodule\n"
    )
    out = json.loads(_run(capsys, "check", "--json", "--synth", "--select", "LNG-016", p)[1])
    assert {(d["rule"], d["severity"]) for d in out["diagnostics"]} == {("LNG-016", "SHOULD")}


def test_baseline_hides_known_findings_and_reports_new_ones(capsys, sv, tmp_path):
    p = sv(CLEAN.replace("    logic", "    reg", 1))  # a LNG-001 to start from
    base = tmp_path / "baseline.json"
    check = ("check", "--no-external", "--select", "LNG-001", "--baseline", base, p)
    assert _run(capsys, *check)[0] == 2  # no baseline file yet
    assert _run(capsys, *check[:-1], "--write-baseline", p)[0] == 0
    assert _run(capsys, *check)[0] == 0
    # Moved down a line it is still known; a second `reg` is new.
    p.write_text("\n" + p.read_text().replace("endmodule", "    reg spare_q;  // S.\nendmodule"))
    code, out, err = _run(capsys, *check)
    assert code == 1 and out.count("LNG-001") == 1 and "1 finding(s) hidden" in err


def test_exclude_skips_discovered_files_but_not_named_ones(capsys, tmp_path):
    (tmp_path / ".svstyle.toml").write_text('exclude = ["vendor/*"]\n')
    (tmp_path / "vendor" / "ip").mkdir(parents=True)
    vendored = tmp_path / "vendor" / "ip" / "x.sv"
    vendored.write_text(CLEAN.replace("    logic", "    reg", 1))
    (tmp_path / "reg_byte.sv").write_text(CLEAN)
    assert _run(capsys, "check", "--no-external", tmp_path)[0] == 0  # the vendored file skipped
    assert _run(capsys, "check", "--no-external", vendored)[0] == 1  # named: checked


def test_missing_include_dir_is_an_error(capsys, sv):
    with pytest.raises(SystemExit) as exc:
        main(["check", "--no-external", "-I", "/no/such/dir", str(sv())])
    assert exc.value.code == 2 and "no such directory" in capsys.readouterr().err


@needs_verible
def test_fix_reports_each_file_on_its_own_when_run_in_parallel(capsys, tmp_path):
    good = tmp_path / "reg_byte.sv"
    good.write_text(CLEAN.replace("    logic", "    reg", 1))
    (tmp_path / "bad.sv").write_text("module bad (;\nendmodule\n")
    code, _, err = _run(capsys, "fix", tmp_path / "bad.sv", good)
    assert code == 3 and "bad.sv" in err
    assert "reg " not in good.read_text()  # the other file was still fixed
