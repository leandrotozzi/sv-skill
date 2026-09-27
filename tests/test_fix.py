from svstyle.fix import token_signature

BASE = "`ifdef A\n  logic x;\n`endif\nmodule m;\nendmodule\n"


def test_signature_ignores_whitespace_and_comments():
    edited = "`ifdef A\n    logic   x;  // new\n`endif\n// Top.\nmodule m; endmodule"
    assert token_signature(edited) == token_signature(BASE)


def test_signature_sees_token_change():
    assert token_signature(BASE.replace("module m", "module n")) != token_signature(BASE)


def test_signature_sees_ifdef_disabled_text():
    assert token_signature(BASE.replace("logic x", "logic y")) != token_signature(BASE)


def test_signature_sees_directive_change():
    assert token_signature(BASE.replace("`ifdef A", "`ifndef A")) != token_signature(BASE)
