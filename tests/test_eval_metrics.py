"""evals/grade.py metrics and evals/run.py ratios: depth of the flattened design."""

import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1] / "evals"))
import grade  # noqa: E402
import run  # noqa: E402

CHAIN = """module sel (
    input  logic       clk_i,
    input  logic [7:0] s_i,  // one-hot
    input  logic [7:0] d_i,
    output logic       y_o
);
    logic y_q;
    always_ff @(posedge clk_i) begin
        y_q <= {body};
    end
    assign y_o = y_q;
endmodule
"""
PRIORITY = " : ".join(f"s_i[{i}] ? d_i[{i}]" for i in range(8)) + " : 1'b0"


@pytest.mark.skipif(not shutil.which("yosys"), reason="yosys missing")
def test_metrics_sees_a_priority_chain_deeper_than_and_or(tmp_path):
    def size(body):
        d = tmp_path / str(len(body))
        d.mkdir()
        (d / "sel.sv").write_text(CHAIN.format(body=body))
        return grade.metrics(d)

    chain, andor = size(PRIORITY), size("|(s_i & d_i)")
    assert chain["depth"] > andor["depth"] > 0
    assert chain["transistors"] > andor["transistors"] > 0
    assert grade.metrics(tmp_path / "empty") == {}  # no RTL: a review eval


@pytest.mark.skipif(not shutil.which("yosys"), reason="yosys missing")
def test_metrics_reads_what_the_builtin_reader_rejects_and_says_why_it_cannot(tmp_path):
    classics = Path(__file__).parents[1] / "evals/files/classics"
    for f in ("alu.sv", "alu_pkg.sv"):  # read_verilog -sv rejects alu
        shutil.copy(classics / f, tmp_path)
    assert grade.metrics(tmp_path)["depth"] > 0
    (tmp_path / "alu.sv").write_text("module alu; logic ; endmodule\n")
    assert grade.metrics(tmp_path)["error"]


def test_ratios_use_correct_runs_and_flag_regressions():
    def row(ev, cfg, depth, correct=True, n=1):
        return {"eval": ev, "config": cfg, "run": n, "depth": depth, "transistors": 100,
                "correct": correct, "has_rtl": True}  # fmt: skip

    unread = {**row("b", "with_skill", 0, n=2), "depth_error": "ERROR: unknown module"}
    del unread["depth"], unread["transistors"]
    rows = [
        row("a", "with_skill", 13), row("a", "without_skill", 10),
        row("a", "without_skill", 1, correct=False, n=2),  # broken: not counted
        row("b", "with_skill", 10), row("b", "without_skill", 10), unread,
    ]  # fmt: skip
    out = run.ratios(rows)
    assert "| a | 1.30 **regression** | 1.00 |" in out
    assert "| b | 1.00 | 1.00 |" in out
    assert "| geomean | 1.14 **regression** | 1.00 |" in out
    assert "- a/without_skill/run-2: fails its testbench" in out
    assert "- b/with_skill/run-2: ERROR: unknown module" in out
