"""Every rule a tool enforces is proven to fire, through `svstyle check` end to end.

This is the rules DB's link to its tests: a rule whose tool mapping is wrong
(a misspelt Verilator code, a Verible rule the config does not enable) has no
snippet that triggers it, and `test_every_enforced_rule_has_a_snippet` names it.
"""

# ruff: noqa: E501  (the snippets are SV source, one rule per line)

import json
import shutil

import pytest

from svstyle.cli import main
from svstyle.rules import load_rules

pytestmark = pytest.mark.skipif(
    not (shutil.which("verible-verilog-lint") and shutil.which("verilator")),
    reason="needs Verible and Verilator",
)

PORTS = (
    "    input  logic clk_i,\n    input  logic rst_ni,\n    input  logic a_i,\n    output logic b_o"
)
SUB = "\nmodule sub (\n    input  logic a_i,\n    output logic b_o\n);\n    assign b_o = a_i;\nendmodule\n"


def mod(body: str, ports: str = PORTS, head: str = "module m (", tail: str = "") -> str:
    return f"{head}\n{ports}\n);\n{body}\nendmodule\n{tail}"


# rule id -> (file name, source). Each source is minimal: it may trip other
# rules too, the test only asks that its own ID is among the findings.
SNIPPETS = {
    "DOC-001": ("m.sv", mod("    assign b_o = a_i;")),
    "DOC-002": ("m.sv", "// Copyright (c) 2026 X\n// All rights reserved\n//\n// Description:\n"
                        "//   TODO: describe\n\n" + mod("    assign b_o = a_i;")),
    "DOC-003": ("m.sv", mod("    assign b_o = a_i;")),
    "STR-005": ("m.sv", "package p_pkg;\nendpackage\nimport p_pkg::*;\n" + mod("    assign b_o = a_i;")),
    "PRT-002": ("m.sv", mod("    assign b_o = a_i;", ports="    input  logic a_i,\n    input  logic clk_i,\n    output logic b_o")),
    "NAM-003": ("m.sv", mod("    assign b_o = a_i & rst_in;", ports="    input  logic rst_in,\n    input  logic a_i,\n    output logic b_o")),
    "LNG-001": ("m.sv", mod("    wire x;\n    assign x = a_i;\n    assign b_o = x;")),
    "SYN-001": ("m.sv", mod("    always_comb begin\n        b_o = 1'b0;\n        case (a_i)  // synopsys full_case\n"
                            "            1'b1: b_o = 1'b1;\n            default: b_o = 1'b0;\n        endcase\n    end")),
    "RST-001": ("m.sv", mod("    logic x_q;\n    always_ff @(posedge clk_i) begin\n        if (rst_ni) begin\n"
                            "            x_q <= 1'b0;\n        end else begin\n            x_q <= a_i;\n        end\n"
                            "    end\n    assign b_o = x_q;")),
    "DOC-004": ("m.sv", mod("    logic x;\n    assign x = a_i;\n    assign b_o = x;")),
    "DOC-005": ("m.sv", mod("    always_comb begin\n        b_o = a_i;\n    end")),
    "DOC-006": ("m.sv", mod("    sub u_sub (\n        .a_i(a_i),\n        .b_o(b_o)\n    );", tail=SUB)),
    "DOC-010": ("m.sv", mod("`ifdef FOO\n    assign b_o = a_i;\n`else\n    assign b_o = 1'b0;\n`endif")),
    "STR-001": ("other.sv", mod("    assign b_o = a_i;")),
    "PRT-001": ("m.sv", "module m (a_i, b_o);\n    input logic a_i;\n    output logic b_o;\n"
                        "    assign b_o = a_i;\nendmodule\n"),
    "PRT-003": ("m.sv", mod("    sub u_sub (a_i, b_o);", tail=SUB)),
    "PRT-004": ("m.sv", mod("    sub u_sub (\n        .a_i(a_i)\n    );\n    assign b_o = a_i;", tail=SUB)),
    "PRT-005": ("m.sv", mod("    sub u_sub (\n        .a_i(a_i),\n        .b_o(b_o)\n    );\n"
                            "    defparam u_sub.W = 2;",
                            tail=SUB.replace("module sub (", "module sub #(\n    parameter int W = 1\n) ("))),
    "NAM-001": ("m.sv", mod("    logic fooBar;\n    assign fooBar = a_i;\n    assign b_o = fooBar;")),
    "NAM-002": ("m.sv", mod("    assign b_o = a;", ports="    input  logic a,\n    output logic b_o")),
    "NAM-004": ("m.sv", mod("    logic cnt;\n    always_ff @(posedge clk_i) begin\n        cnt <= a_i;\n"
                            "    end\n    assign b_o = cnt;")),
    "NAM-005": ("m.sv", mod("    typedef enum logic {A, B} state;\n    state s;\n    assign s = A;\n"
                            "    assign b_o = a_i;")),
    "NAM-006": ("m.sv", mod("    assign b_o = a_i;", head="module m #(\n    parameter int depth = 1\n) (")),
    "NAM-007": ("m.sv", mod("    assign b_o = a_i;",
                            head="module m #(\n    parameter bit DisableFoo = 0\n) (")),
    "NAM-008": ("m.sv", "`define foo 1\n" + mod("    assign b_o = a_i;")),
    "FMT-001": ("m.sv", mod("\tassign b_o = a_i;")),
    "FMT-002": ("m.sv", mod("    assign    b_o=a_i;")),
    "FMT-003": ("m.sv", mod("    always_comb\n        if (a_i) b_o = 1'b1;\n        else b_o = 1'b0;")),
    "FMT-004": ("m.sv", mod("    assign b_o = a_i;;")),
    "FMT-005": ("m.sv", mod("    assign b_o = a_i ? clk_i ? 1'b1 : 1'b0 : 1'b0;")),
    "LNG-002": ("m.sv", mod("    logic x_q;\n    always_ff @(posedge clk_i) begin\n        x_q = a_i;\n"
                            "    end\n    assign b_o = x_q;")),
    "LNG-003": ("m.sv", mod("    always @* begin\n        b_o = a_i;\n    end")),
    "LNG-004": ("m.sv", mod("    always_comb begin\n        b_o <= a_i;\n    end")),
    "LNG-005": ("m.sv", mod("    logic x_q;\n    always_ff @(posedge clk_i) begin\n        x_q <= a_i;\n"
                            "    end\n    always_ff @(negedge clk_i) begin\n        x_q <= rst_ni;\n"
                            "    end\n    assign b_o = x_q;")),
    "LNG-006": ("m.sv", mod("    always_comb begin\n        if (a_i) begin\n            b_o = 1'b1;\n"
                            "        end\n    end")),
    "LNG-007": ("m.sv", mod("    always_comb begin\n        b_o = 1'b0;\n        case (a_i)\n"
                            "            1'b1: b_o = 1'b1;\n        endcase\n    end")),
    "LNG-008": ("m.sv", mod("    logic [7:0] x;\n    assign x = 8'b1;\n    assign b_o = x[0] & a_i;")),
    "LNG-009": ("m.sv", mod("    always_comb begin\n        casex (a_i)\n            1'b1: b_o = 1'b1;\n"
                            "            default: b_o = 1'b0;\n        endcase\n    end")),
    "LNG-010": ("m.sv", mod("    function logic inv(input logic x);\n        return ~x;\n"
                            "    endfunction\n    assign b_o = inv(a_i);")),
    "LNG-011": ("m.sv", mod("    parameter int X = 1;\n    assign b_o = a_i;")),
    "LNG-012": ("m.sv", mod("    logic [0:3] x;\n    assign x = '0;\n    assign b_o = x[0] & a_i;")),
    "LNG-013": ("m.sv", mod("    initial begin\n        $display(\"%d\", $random);\n    end\n"
                            "    assign b_o = a_i;")),
    "LNG-014": ("m.sv", mod("    assign b_o = a_i;")),
    "LNG-015": ("m.sv", mod("    assign b_o = a_i;\n    logic [1:0] y;\n    assign y = {a_i, a_i, a_i};\n"
                            "    logic z;\n    assign z = y[0];")),
    "LNG-016": ("m.sv", mod("    logic x;\n    assign b_o = x & a_i;")),
    "LNG-017": ("m.sv", mod("    logic x;\n    assign x = a_i;\n    assign b_o = a_i;")),
    "RST-005": ("m.sv", mod("    logic x_q, y_q;\n    always_ff @(posedge clk_i or negedge rst_ni) begin\n"
                            "        if (!rst_ni) begin\n            x_q <= 1'b0;\n        end else begin\n"
                            "            x_q <= a_i;\n        end\n    end\n"
                            "    always_ff @(posedge clk_i) begin\n        y_q <= rst_ni;\n    end\n"
                            "    assign b_o = x_q & y_q;")),
    "GEN-001": ("m.sv", mod("    logic [1:0] x;\n    for (genvar i = 0; i < 2; i++) begin\n"
                            "        assign x[i] = a_i;\n    end\n    assign b_o = &x;")),
    "GEN-002": ("m.sv", mod("    logic [1:0] x;\n    genvar i;\n    generate\n"
                            "        for (i = 0; i < 2; i++) begin : gen_x\n            assign x[i] = a_i;\n"
                            "        end\n    endgenerate\n    assign b_o = &x;")),
}  # fmt: skip


def test_every_enforced_rule_has_a_snippet():
    enforced = {r.id for r in load_rules() if r.tool != "review"}
    assert enforced == set(SNIPPETS), (
        f"missing: {sorted(enforced - set(SNIPPETS))}; stale: {sorted(set(SNIPPETS) - enforced)}"
    )


@pytest.mark.parametrize("rid", sorted(SNIPPETS))
def test_rule_fires_end_to_end(rid, tmp_path, monkeypatch, capsys):
    name, text = SNIPPETS[rid]
    monkeypatch.chdir(tmp_path)  # Verilator resolves nothing outside the snippet
    (tmp_path / name).write_text(text)
    main(["check", "--json", name])
    found = {d["rule"] for d in json.loads(capsys.readouterr().out)["diagnostics"]}
    assert rid in found, sorted(found)
