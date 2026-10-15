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
    assert grade.metrics(tmp_path / "empty") == {}


def test_ratios_use_correct_runs_and_flag_regressions():
    def row(ev, cfg, depth, correct=True):
        return {"eval": ev, "config": cfg, "depth": depth, "transistors": 100, "correct": correct}

    rows = [
        row("a", "with_skill", 13), row("a", "without_skill", 10),
        row("a", "without_skill", 1, correct=False),  # broken: not counted
        row("b", "with_skill", 10), row("b", "without_skill", 10),
    ]  # fmt: skip
    out = run.ratios(rows)
    assert "| a | 1.30 **regression** | 1.00 |" in out
    assert "| b | 1.00 | 1.00 |" in out
    assert "| geomean | 1.14 **regression** | 1.00 |" in out
