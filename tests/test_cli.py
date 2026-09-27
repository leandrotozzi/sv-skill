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


# --- fix ------------------------------------------------------------------------


@needs_verible
def test_fix_writes_file_and_leaves_it_check_clean(capsys, sv):
    p = sv(CLEAN.replace("rst_ni,  // Asynchronous reset, active-low", "rst_ni,"))
    code, out, _ = _run(capsys, "fix", p)
    assert code == 0 and "fixed 1 file" in out
    assert "rst_ni,  // TODO: describe" in p.read_text()
    assert _run(capsys, "check", "--no-external", p)[0] == 0


@needs_verible
def test_fix_diff_does_not_write(capsys, sv):
    text = CLEAN.replace("rst_ni,  // Asynchronous reset, active-low", "rst_ni,")
    p = sv(text)
    code, out, _ = _run(capsys, "fix", "--diff", p)
    assert code == 0 and "+    input  logic             rst_ni,  // TODO: describe" in out
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
    assert code == 4 and "non-whitespace token" in err
    assert p.read_text() == CLEAN
