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
