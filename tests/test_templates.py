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
TB = ASSETS / "skeleton_tb.sv"  # a testbench, not RTL: the house rules do not apply
TEMPLATES = sorted({*ASSETS.glob("*.sv"), *ASSETS.glob("*.svh")} - {TB})
RTL = sorted(
    (p for p in TEMPLATES if p.suffix == ".sv"),
    key=lambda p: (not p.name.endswith("_pkg.sv"), p.name),
)
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


PULSE_TB = """`include "assert_macros.svh"
module t;
    logic clk_i = 0, rst_ni = 0, v_q;
    always #5 clk_i = ~clk_i;
    always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) v_q <= 1'b0; else v_q <= ($time < DROP);
    `ASSERT(Hold_A, v_q |=> v_q)
    initial begin
        #12 rst_ni = 1;
        #30 rst_ni = 0;  // a pulse between the edges at 35 and 45
        #2 rst_ni = 1;
        #80 $display("DONE");
        $finish;
    end
endmodule
"""


@needs_tools
@pytest.mark.parametrize(("drop", "fires"), [(1000, False), (60, True)])
def test_assert_survives_a_reset_pulse_between_edges(tmp_path, drop, fires):
    """Verilator samples `disable iff` only at edges; the macro must still skip
    the check a short reset cut short, yet catch a real drop after it."""
    (tmp_path / "t.sv").write_text(PULSE_TB.replace("DROP", str(drop)))
    build = subprocess.run(
        ["verilator", "--binary", "--timing", "-Wno-fatal", "-Wno-lint", "-Wno-style",
         f"-I{ASSETS}", "--top-module", "t", "t.sv"],
        cwd=tmp_path, capture_output=True, text=True,
    )  # fmt: skip
    assert build.returncode == 0, build.stderr
    sim = subprocess.run(["obj_dir/Vt"], cwd=tmp_path, capture_output=True, text=True)
    assert ("Hold_A failed" in sim.stdout + sim.stderr) == fires


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


def simulate(tmp_path: Path, dut: str) -> subprocess.CompletedProcess:
    """Build and run the testbench template the way testbench-verilator.md says."""
    (tmp_path / "dut.sv").write_text(dut)
    build = subprocess.run(
        ["verilator", "--binary", "--timing", "--assert", "-Wno-fatal", "--x-assign", "unique",
         "--x-initial", "unique", f"-I{ASSETS}", "--top-module", TB.stem, "dut.sv", str(TB)],
        cwd=tmp_path, capture_output=True, text=True,
    )  # fmt: skip
    assert build.returncode == 0, build.stderr
    run = [f"obj_dir/V{TB.stem}", "+verilator+rand+reset+2"]
    return subprocess.run(run, cwd=tmp_path, capture_output=True, text=True)


@needs_tools
def test_testbench_template_passes_on_the_skeleton(tmp_path):
    sim = simulate(tmp_path, (ASSETS / "skeleton.sv").read_text())
    assert sim.returncode == 0 and "PASS: " in sim.stdout, sim.stdout + sim.stderr


@needs_tools
@pytest.mark.parametrize(
    ("good", "bad"),
    [("valid_d = valid_i;", "valid_d = valid_i && !data_i[7];"),  # a wrong output
     ("valid_q <= 1'b0;", "valid_q <= valid_q;")],  # a missing reset
)  # fmt: skip
def test_testbench_template_fails_on_a_planted_bug(tmp_path, good, bad):
    sim = simulate(tmp_path, (ASSETS / "skeleton.sv").read_text().replace(good, bad))
    assert sim.returncode != 0 and "FAIL: " in sim.stdout + sim.stderr


@pytest.mark.parametrize("path", [*TEMPLATES, TB], ids=lambda p: p.name)
def test_template_lines_fit_100_columns(path):
    # Verible's line-length skips comment-only lines, so check every line here.
    assert [n for n, ln in enumerate(path.read_text().splitlines(), 1) if len(ln) > 100] == []
