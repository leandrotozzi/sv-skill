from datetime import date
from pathlib import Path

import pytest

from svstyle.checks import HEADER, PLACEHOLDER, ConfigError, load_config, run_checks
from svstyle.rules import load_rules

RULES = load_rules()
CLEAN = (Path(__file__).parent / "fixtures" / "input" / "clean.sv").read_text()


def _check(text, path="reg_byte.sv"):
    return run_checks(text, path, RULES)


def _found(text, path="reg_byte.sv"):
    return [(d.rule, d.line) for d in _check(text, path)]


def _edit(old, new, text=CLEAN):
    assert text.count(old) == 1, old
    return text.replace(old, new)


def test_clean_file_has_no_findings():
    assert _check(CLEAN) == []


# --- DOC-001 / DOC-002: header ----------------------------------------------------


def test_missing_header_is_fixable_at_top():
    text = CLEAN[CLEAN.index("`default_nettype") :]
    (d,) = [d for d in _check(text) if d.rule == "DOC-001"]
    header = HEADER.format(year=date.today().year, company=PLACEHOLDER)
    assert (d.line, d.severity, d.fix) == (1, "MUST", (0, header))


def test_foreign_licence_header_gets_ours_above_it():
    text = "// SPDX-License-Identifier: Apache-2.0\n" + CLEAN[CLEAN.index("`default_nettype") :]
    (d,) = [d for d in _check(text) if d.rule == "DOC-001"]
    assert d.fix[0] == 0  # inserted above; the licence line is kept


def test_malformed_existing_header_is_not_autofixed():
    text = _edit("// All rights reserved\n", "")
    (d,) = [d for d in _check(text) if d.rule == "DOC-001"]
    assert d.fix is None


def test_todo_description_is_flagged():
    text = _edit(
        "//   Registers a payload for one cycle and drives it out through a second\n"
        "//   flop stage, so both input and output are registered.\n",
        "//   TODO: describe\n",
    )
    assert _found(text) == [("DOC-002", 4)]


def test_one_line_restatement_is_flagged():
    text = _edit(
        "//   Registers a payload for one cycle and drives it out through a second\n"
        "//   flop stage, so both input and output are registered.\n",
        "//   Register module.\n",
    )
    assert _found(text) == [("DOC-002", 4)]


def test_placeholder_company_warns():
    (d,) = _check(_edit("ACME Corp", PLACEHOLDER))
    assert (d.rule, d.line, d.severity) == ("DOC-001", 1, "SHOULD")


# --- DOC-003 / DOC-004: trailing comments -----------------------------------------


def test_port_without_comment():
    (d,) = _check(_edit("rst_ni,  // Asynchronous reset, active-low", "rst_ni,"))
    assert (d.rule, d.line, d.severity, d.fixable) == ("DOC-003", 14, "MUST", True)
    assert d.fix[1] == "  // TODO: describe"


def test_param_and_signal_without_comment():
    text = _edit("  // Payload width in bits", "")
    text = _edit("  // First-stage register", "", text)
    assert _found(text) == [("DOC-004", 11), ("DOC-004", 18)]


def test_multiline_declaration_may_carry_its_comment_above():
    # A default value spread over lines has no single end to trail a comment on.
    text = _edit(
        "    logic [Width-1:0] q_q;  // First-stage register",
        "    // First-stage register\n    logic [Width-1:0] q_q = {\n        Width'(0)\n    };",
    )
    assert _found(text) == []
    # One line still needs it trailing: above is only for what does not fit.
    text = _edit(
        "    logic [Width-1:0] q_q;  // First-stage register",
        "    // First-stage register\n    logic [Width-1:0] q_q;",
    )
    assert _found(text) == [("DOC-004", 19)]
    # One line that its comment would push past 100 columns may also carry it above.
    long = "    // " + "x" * 80 + "\n    logic [Width-1:0] q_q;"
    assert _found(_edit("    logic [Width-1:0] q_q;  // First-stage register", long)) == []


def test_anchor_in_macro_is_reported_but_not_fixable():
    text = _edit(
        "    logic [Width-1:0] q_q;", "`define DECL logic x;\n    `DECL\n    logic [Width-1:0] q_q;"
    )
    (d,) = [d for d in _check(text) if d.rule == "DOC-004"]
    assert (d.fixable, d.fix) == (False, None)


# --- DOC-005 / DOC-006: comment above -----------------------------------------------


def test_block_without_comment():
    (d,) = _check(_edit("    // Capture the payload.\n", ""))
    assert (d.rule, d.line, d.fix[1]) == ("DOC-005", 20, "// TODO: describe\n")


def test_instance_without_comment():
    assert _found(_edit("    // Second stage keeps the output registered.\n", "")) == [
        ("DOC-006", 29)
    ]


# --- PRT-001 / PRT-003: ports and connections ---------------------------------------


def test_non_ansi_ports():
    text = "module m (a_i);\n    input logic a_i;  // In\nendmodule\n"
    assert ("PRT-001", 1) in _found(text, "m.sv")


def test_two_ports_on_one_line():
    text = _edit(
        "    input  logic [Width-1:0] d_i,     // Payload in\n",
        "    input  logic [Width-1:0] d_i, e_i,  // Payload in\n",
    )
    assert _found(text) == [("PRT-001", 15)]


@pytest.mark.parametrize(
    "conn", ["(clk_i, q_q, q_o)", "(.*)", "(.clk_i(clk_i), q_q, q_o)"], ids=str
)
def test_instance_not_named(conn):
    start = CLEAN.index(" u_out (") + len(" u_out ")
    end = CLEAN.index(");\nendmodule") + 1
    text = CLEAN[:start] + conn + CLEAN[end:]
    assert _found(text) == [("PRT-003", 30)]


# --- LNG-014: default_nettype -----------------------------------------------------


def test_missing_default_nettype_and_resetall():
    text = _edit("`default_nettype none\n\n", "")
    text = _edit("\n`resetall\n", "", text)
    found = [d for d in _check(text) if d.rule == "LNG-014"]
    assert [(d.line, d.fix) for d in found] == [
        (8, (text.index("module"), "`default_nettype none\n\n")),
        (text.count("\n"), (len(text), "\n`resetall\n")),
    ]


def test_default_nettype_not_required_in_svh():
    text = _edit("`default_nettype none\n\n", "")
    text = _edit("\n`resetall\n", "", text)
    assert "LNG-014" not in {d.rule for d in _check(text, "reg_byte.svh")}


def test_port_continuing_previous_declaration_on_its_own_line():
    text = _edit(
        "    input  logic [Width-1:0] d_i,     // Payload in\n",
        "    input  logic [Width-1:0] d_i,     // Payload in\n    e_i,  // Second payload\n",
    )
    assert _found(text) == [("PRT-001", 16)]


# --- .svstyle.toml: the company in the header ---------------------------------------


def test_missing_header_uses_configured_company():
    text = CLEAN[CLEAN.index("`default_nettype") :]
    (d,) = [
        d for d in run_checks(text, "reg_byte.sv", RULES, company="Foo Inc") if d.rule == "DOC-001"
    ]
    assert d.fix[1].startswith(f"// Copyright (c) {date.today().year} Foo Inc\n")


def test_placeholder_is_replaced_from_config():
    text = _edit("ACME Corp", PLACEHOLDER)
    (d,) = run_checks(text, "reg_byte.sv", RULES, company="Foo Inc")
    off, new, old_len = d.fix
    assert (d.rule, d.severity) == ("DOC-001", "SHOULD")
    assert text[:off] + new + text[off + old_len :] == CLEAN.replace("ACME Corp", "Foo Inc")


def test_placeholder_without_config_points_at_the_config_file():
    (d,) = _check(_edit("ACME Corp", PLACEHOLDER))
    assert d.fix is None and ".svstyle.toml" in d.message


def test_config_is_found_walking_up(tmp_path):
    (tmp_path / ".svstyle.toml").write_text('company = "Foo Inc"\n')
    (tmp_path / "rtl" / "sub").mkdir(parents=True)
    assert load_config(tmp_path / "rtl" / "sub" / "m.sv") == {"company": "Foo Inc"}


def test_no_config_is_empty(tmp_path):
    assert load_config(tmp_path / "m.sv") == {}


def test_config_rejects_unknown_keys(tmp_path):
    (tmp_path / ".svstyle.toml").write_text('compnay = "typo"\n')
    with pytest.raises(ConfigError, match="compnay"):
        load_config(tmp_path / "m.sv")


# --- M4: review rules made mechanical ---------------------------------------------


@pytest.mark.parametrize(
    "old,new,rid,line",
    [
        ("    logic [Width-1:0] q_q;", "    reg [Width-1:0] q_q;", "LNG-001", 18),
        ("    logic [Width-1:0] q_q;", "    wire [Width-1:0] q_q;", "LNG-001", 18),
        (
            "    input  logic             rst_ni,",
            "    input  wire              rst_ni,",
            "LNG-001",
            14,
        ),
        ("if (!rst_ni) begin", "if (!rst_ni) begin  // synopsys full_case", "SYN-001", 22),
        ("module reg_byte #(", "(* parallel_case *)\nmodule reg_byte #(", "SYN-001", 10),
    ],
    ids=["reg", "wire", "wire-port", "full_case", "parallel_case-attr"],
)
def test_forbidden_constructs(old, new, rid, line):
    assert (rid, line) in _found(_edit(old, new))


def test_full_case_mentioned_in_prose_is_not_a_directive():
    text = _edit("// Capture the payload.", "// Capture the payload; no full_case needed.")
    assert "SYN-001" not in {d.rule for d in _check(text)}


def test_reg_inside_a_comment_or_string_is_ignored():
    text = _edit("// Capture the payload.", "// Capture the payload into a reg or wire.")
    assert "LNG-001" not in {d.rule for d in _check(text)}


def test_clock_and_reset_come_first():
    text = _edit(
        "    input  logic             clk_i,   // System clock\n"
        "    input  logic             rst_ni,  // Asynchronous reset, active-low\n"
        "    input  logic [Width-1:0] d_i,     // Payload in\n",
        "    input  logic [Width-1:0] d_i,     // Payload in\n"
        "    input  logic             clk_i,   // System clock\n"
        "    input  logic             rst_ni,  // Asynchronous reset, active-low\n",
    )
    assert _found(text) == [("PRT-002", 13)]


def test_reset_before_clock_is_out_of_order():
    text = _edit(
        "    input  logic             clk_i,   // System clock\n"
        "    input  logic             rst_ni,  // Asynchronous reset, active-low\n",
        "    input  logic             rst_ni,  // Asynchronous reset, active-low\n"
        "    input  logic             clk_i,   // System clock\n",
    )
    assert _found(text) == [("PRT-002", 13)]


def test_each_clock_opens_its_own_domain_group():
    """lowRISC CDC style: clk_wr_i, rst_wr_ni, write side, clk_rd_i, rst_rd_ni, read side."""
    text = _edit(
        "    output logic [Width-1:0] q_o      // Payload, two cycles later\n",
        "    output logic [Width-1:0] q_o,     // Payload, two cycles later\n"
        "    input  logic             clk_rd_i,   // Read clock\n"
        "    input  logic             rst_rd_ni,  // Read reset\n"
        "    output logic             empty_o     // Read side\n",
    )
    assert "PRT-002" not in {d.rule for d in _check(text)}


def test_a_reset_after_the_rest_of_its_group_is_out_of_order():
    text = _edit(
        "    output logic [Width-1:0] q_o      // Payload, two cycles later\n",
        "    output logic [Width-1:0] q_o,     // Payload, two cycles later\n"
        "    input  logic             rst_sw_ni   // Software reset\n",
    )
    assert ("PRT-002", 17) in _found(text)


def test_active_low_suffix_order():
    text = _edit("rst_ni,  // Asynchronous", "rst_in,  // Asynchronous")
    assert ("NAM-003", 14) in _found(text)


def test_file_scope_import():
    text = _edit("module reg_byte #(", "import foo_pkg::*;\n\nmodule reg_byte #(")
    assert ("STR-005", 10) in _found(text)


def test_import_in_the_module_header_is_fine():
    text = _edit("module reg_byte #(", "module reg_byte\n    import foo_pkg::*;\n#(")
    assert "STR-005" not in {d.rule for d in _check(text)}


@pytest.mark.parametrize(
    "old,new",
    [
        ("@(posedge clk_i or negedge rst_ni)", "@(posedge clk_i or posedge rst_i)"),
        ("@(posedge clk_i or negedge rst_ni)", "@(posedge clk_i)"),
    ],
    ids=["active-high-async", "synchronous"],
)
def test_reset_style(old, new):
    text = _edit(old, new)
    text = text.replace("if (!rst_ni)", "if (!rst_ni)" if "negedge" in new else "if (rst_i)")
    text = text.replace("rst_ni,  // Asynchronous", "rst_i,   // Asynchronous")
    assert ("RST-001", 21) in _found(text)


def test_unreset_datapath_flop_is_not_a_reset_style_finding():
    text = _edit(
        "    // Second stage",
        "    // Datapath copy, deliberately not reset.\n"
        "    always_ff @(posedge clk_i) begin\n        q_q2 <= q_q;\n    end\n\n"
        "    // Second stage",
    )
    assert "RST-001" not in {d.rule for d in _check(text)}


# --- DOC-009: inline waivers --------------------------------------------------------


def test_waiver_on_the_line_above_silences_one_rule():
    text = _edit(
        "    logic [Width-1:0] q_q;",
        "    // svstyle: waive LNG-001 -- vendor macro expects a net\n    wire [Width-1:0] q_q;",
    )
    assert "LNG-001" not in {d.rule for d in _check(text)}


def test_trailing_waiver_silences_that_line_only():
    text = _edit(
        "    logic [Width-1:0] q_q;  // First-stage register",
        "    wire [Width-1:0] q_q;  // svstyle: waive LNG-001 tri-state pad\n"
        "    wire [Width-1:0] r_q;  // Not waived",
    )
    assert [f for f in _found(text) if f[0] == "LNG-001"] == [("LNG-001", 19)]


def test_waiver_without_a_reason_does_not_count():
    text = _edit(
        "    logic [Width-1:0] q_q;", "    // svstyle: waive LNG-001\n    wire [Width-1:0] q_q;"
    )
    assert "LNG-001" in {d.rule for d in _check(text)}


def test_waived_finding_is_not_autofixed():
    text = _edit("  // First-stage register", "")
    text = _edit(
        "    logic [Width-1:0] q_q;",
        "    // svstyle: waive DOC-004 obvious\n    logic [Width-1:0] q_q;",
        text,
    )
    assert "DOC-004" not in {d.rule for d in _check(text)}


def test_import_in_the_body_of_a_lone_unit_is_not_file_scope():
    """pyslang makes a file's only design unit the root: its members are not the file's."""
    text = _edit("    logic [Width-1:0] q_q;", "    import foo_pkg::*;\n    logic [Width-1:0] q_q;")
    assert "STR-005" not in {d.rule for d in _check(text)}


def test_scan_reset_groups_with_the_test_interface():
    text = _edit(
        "    output logic [Width-1:0] q_o      // Payload, two cycles later\n",
        "    output logic [Width-1:0] q_o,     // Payload, two cycles later\n"
        "    input  logic             scan_rst_ni  // DFT scan reset\n",
    )
    assert "PRT-002" not in {d.rule for d in _check(text)}


# --- SYN-006: initial blocks -------------------------------------------------------


def test_initial_block_in_rtl():
    text = _edit(
        "    // Capture the payload.",
        "    initial begin\n        q_q = '0;\n    end\n\n    // Capture the payload.",
    )
    assert ("SYN-006", 20) in _found(text)


def test_initial_block_under_a_guard_or_from_a_macro_is_fine():
    guarded = _edit(
        "    // Capture the payload.",
        '`ifndef SYNTHESIS\n    initial begin\n        $display("sim");\n    end\n'
        "`endif  // SYNTHESIS\n\n"
        "    // Capture the payload.",
    )
    macro = _edit(
        "    // Capture the payload.",
        "`define CHECK initial begin end\n    `CHECK\n\n    // Capture the payload.",
    )
    for text in (guarded, macro):
        assert "SYN-006" not in {d.rule for d in _check(text)}
