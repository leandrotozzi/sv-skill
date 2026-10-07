from pathlib import Path

import pytest

from svstyle.parse import ParseError, parse

FIXTURES = Path(__file__).parent / "fixtures" / "input"


def _golden(src):
    return [(a.kind, a.name, a.line, a.comment) for a in src.anchors]


def test_kitchen_sink_anchors():
    src = parse((FIXTURES / "kitchen_sink.sv").read_text(), "kitchen_sink.sv")
    assert _golden(src) == [
        ("decl", "Depth", 8, "// Entries per lane"),
        ("decl", "valid", 13, "// Beat valid"),
        ("decl", "ready", 14, None),
        ("param", "Lanes", 19, "// Number of lanes"),
        ("param", "Width", 20, None),
        ("port", "clk_i", 22, "// Clock"),
        ("port", "rst_ni", 23, None),
        ("port", "data_i, mask_i", 24, "// Packed lanes"),
        ("port", "bus", 25, None),
        ("port", "mem_o", 26, None),
        ("decl", "Total", 30, None),
        ("decl", "mem_q", 31, "// Unpacked storage"),
        ("decl", "any_w", 32, None),
        ("block", "always_ff", 39, "// Register every lane."),
        ("block", "always_comb", 48, None),
        ("decl", "lane_q", 53, "// Per-lane flag"),
        ("instance", "u_buf", 55, "// One buffer per lane."),
        ("instance", "u_pos", 62, None),
        ("instance", "u_wild", 63, None),
    ]


def test_instance_connection_style():
    src = parse((FIXTURES / "kitchen_sink.sv").read_text(), "kitchen_sink.sv")
    style = {a.name: a.detail for a in src.anchors if a.kind == "instance"}
    assert style == {"u_buf": "named", "u_pos": "ordered", "u_wild": "wildcard"}


def test_trailing_offset_is_end_of_last_token_on_line():
    text = "module m (\n    input logic a_i,\n    output logic b_o\n);\nendmodule\n"
    a_i, b_o = parse(text).anchors
    assert text[: a_i.offset].endswith("a_i,")
    assert text[: b_o.offset].endswith("b_o")


def test_above_offset_is_start_of_line():
    text = "module m;\n    always_comb begin\n    end\nendmodule\n"
    (blk,) = parse(text).anchors
    assert text[blk.offset :].startswith("    always_comb")


def test_comment_above_must_be_on_its_own_line():
    text = "module m;\n    logic a;  // trailing, not above\n    always_comb a = 1;\nendmodule\n"
    blk = parse(text).anchors[-1]
    assert (blk.kind, blk.comment) == ("block", None)


def test_block_comment_is_not_a_line_comment():
    text = "module m;\n    logic a;  /* no */\nendmodule\n"
    assert parse(text).anchors[0].comment is None


def test_parse_error_raises():
    with pytest.raises(ParseError, match=r"bad\.sv:2:"):
        parse("module m;\n    logic ;\nendmodule\n", "bad.sv")


def test_non_ansi_module_reported():
    src = parse("module m (a, b);\n    input a;\n    output b;\nendmodule\n")
    assert src.non_ansi == [("m", 1)]


def test_macro_anchor_not_fixable():
    text = "`define DECL logic x;\nmodule m;\n    `DECL\nendmodule\n"
    (a,) = parse(text).anchors
    assert (a.name, a.fixable) == ("`DECL", False)  # what the author wrote, not the expansion


def test_directive_in_port_list_makes_ports_unfixable():
    text = (
        "module m (\n    input logic a_i,\n`ifdef X\n    input logic b_i,\n`endif\n"
        "    output logic c_o\n);\nendmodule\n"
    )
    assert [(a.name, a.fixable) for a in parse(text).anchors] == [
        ("a_i", False),
        ("c_o", False),
    ]


def test_trailing_comment_before_an_ifdef_is_found():
    text = (
        "module m;\n    wire a;  // c\n\n`ifdef X\n    logic d;\n`endif\n    logic b;\nendmodule\n"
    )
    assert parse(text).anchors[0].comment == "// c"


def test_trailing_comment_before_an_implicit_type_port_is_found():
    text = "module m (\n    input logic a_i,  // a\n    b_i  // b\n);\nendmodule\n"
    assert [(a.name, a.comment) for a in parse(text).anchors] == [("a_i", "// a"), ("b_i", "// b")]


def test_multi_declarator_statement_is_one_anchor():
    text = "module m;\n    logic a_q, a_d;  // pair\n    localparam int A = 1, B = 2;\nendmodule\n"
    assert [(a.name, a.comment) for a in parse(text).anchors] == [
        ("a_q, a_d", "// pair"),
        ("A, B", None),
    ]


def test_include_resolves_next_to_the_file_and_on_include_dirs(tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    (tmp_path / "a" / "foo.svh").write_text("`define FOO(x) logic x;\n")
    (tmp_path / "b" / "bar.svh").write_text("`define BAR(x) logic x;\n")
    f = tmp_path / "a" / "m.sv"
    f.write_text(
        '`include "foo.svh"\n`include "bar.svh"\nmodule m;\n    `FOO(a)\n    `BAR(b)\nendmodule\n'
    )
    src = parse(f.read_text(), str(f), include_dirs=[str(tmp_path / "b")])
    assert [a.name for a in src.anchors] == ["`FOO", "`BAR"]


def test_missing_include_hints_at_include_dirs(tmp_path):
    f = tmp_path / "m.sv"
    f.write_text('`include "nope.svh"\nmodule m;\nendmodule\n')
    with pytest.raises(ParseError, match="-I"):
        parse(f.read_text(), str(f))


def test_declarations_from_an_included_file_are_not_anchored(tmp_path):
    (tmp_path / "decls.svh").write_text("logic from_include;\nlogic other;\n")
    f = tmp_path / "m.sv"
    f.write_text('module m;\n    `include "decls.svh"\n    logic own;  // Own\nendmodule\n')
    src = parse(f.read_text(), str(f))
    assert [(a.name, a.line, a.comment) for a in src.anchors] == [("own", 3, "// Own")]


def test_an_include_inside_a_block_counts_as_a_directive(tmp_path):
    (tmp_path / "body.svh").write_text("y = a;\n")
    text = "module m (input logic a, output logic y);\n  always @(*) begin\n"
    text += '    `include "body.svh"\n  end\nendmodule\n'
    src = parse(text, str(tmp_path / "m.sv"))
    assert not any(ins == "always_comb" for _, ins, _ in src.rewrites)
