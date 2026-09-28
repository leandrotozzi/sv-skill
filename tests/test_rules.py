"""The loader is the schema gate for rules.toml, so its rejections are the test."""

import pytest

from svstyle.docgen import render_html, render_markdown_compact, render_markdown_full
from svstyle.rules import RulesError, by_category, load_rules, tool_index

GOOD = """
[[rule]]
id        = "PRT-003"
title     = "Every port carries a trailing comment"
severity  = "MUST"
category  = "PRT"
statement = "Each ANSI port declaration ends with a `//` comment describing the signal."
rationale = "The port list is the module's contract."
good      = "input logic clk_i,  // System clock"
bad       = "input logic clk_i,"
sources   = ["house style"]
[rule.enforcement]
tool    = "svstyle"
rule    = "port_comment"
autofix = true

[[rule]]
id        = "NAM-001"
title     = "Directional port suffixes"
severity  = "MUST"
category  = "NAM"
statement = "Ports end in `_i`, `_o` or `_io`."
rationale = "Direction is visible at every use site, not only in the port list."
sources   = ["lowRISC"]
[rule.enforcement]
tool = "verible-lint"
rule = "port-name-suffix"

[[rule]]
id        = "RST-001"
title     = "Reset policy"
severity  = "SHOULD"
category  = "RST"
statement = "Resets are asynchronous and active-low."
rationale = "Matches the lowRISC/PULP ecosystem this style descends from."
sources   = ["house style"]
[rule.enforcement]
tool = "review"
"""


def write(tmp_path, text):
    p = tmp_path / "rules.toml"
    p.write_text(text, encoding="utf-8")
    return p


def test_loads_and_sorts_by_category_order(tmp_path):
    rules = load_rules(write(tmp_path, GOOD))
    assert [r.id for r in rules] == ["PRT-003", "NAM-001", "RST-001"]
    assert rules[0].autofix is True
    assert rules[1].autofix is False
    assert rules[0].sources == ("house style",)


def test_indexes(tmp_path):
    rules = load_rules(write(tmp_path, GOOD))
    assert list(by_category(rules)) == ["PRT", "NAM", "RST"]
    assert tool_index(rules, "verible-lint")["port-name-suffix"].id == "NAM-001"
    assert tool_index(rules, "review") == {}


# (old, new, expected message). new == "" deletes the line.
@pytest.mark.parametrize(
    "old,new,message",
    [
        ('id        = "PRT-003"', "", "missing or empty id"),
        ('category  = "PRT"', "", "missing or empty category"),
        ('severity  = "MUST"', "", "missing or empty severity"),
        ('rationale = "The port list is the module\'s contract."', "", "missing or empty rat"),
        ('tool    = "svstyle"', "", "enforcement.tool must be one of"),
        ('rule    = "port_comment"', "", "enforcement.rule is required"),
        ('id        = "PRT-003"', 'id        = "PRT-3"', "must look like"),
        ('severity  = "MUST"', 'severity  = "SHALL"', "severity must be one of"),
        ('tool    = "svstyle"', 'tool    = "clang-format"', "enforcement.tool must be one of"),
        ('tool = "review"', 'tool = "review"\nautofix = true', "cannot autofix"),
    ],
)
def test_rejects_malformed(tmp_path, old, new, message):
    assert old in GOOD, "the fixture drifted; this case edits nothing"
    with pytest.raises(RulesError, match=message):
        load_rules(write(tmp_path, GOOD.replace(old, new, 1)))


def test_rejects_unknown_category_prefix(tmp_path):
    bad = GOOD.replace('id        = "PRT-003"', 'id        = "XXX-003"', 1)
    bad = bad.replace('category  = "PRT"', 'category  = "XXX"', 1)
    with pytest.raises(RulesError, match="unknown category prefix"):
        load_rules(write(tmp_path, bad))


def test_rejects_category_disagreeing_with_id(tmp_path):
    with pytest.raises(RulesError, match="disagrees with the id prefix"):
        load_rules(write(tmp_path, GOOD.replace('category  = "PRT"', 'category  = "NAM"', 1)))


def test_rejects_duplicate_id(tmp_path):
    dup = GOOD.replace('id        = "NAM-001"\ntitle', 'id        = "NAM-001"\ntitle')
    dup = dup.replace(
        'id        = "PRT-003"\ntitle     = "Every port carries a trailing comment"',
        'id        = "NAM-001"\ntitle     = "Every port carries a trailing comment"',
    ).replace('category  = "PRT"', 'category  = "NAM"', 1)
    with pytest.raises(RulesError, match="duplicate id"):
        load_rules(write(tmp_path, dup))


def test_rejects_unknown_key(tmp_path):
    with pytest.raises(RulesError, match="unknown key"):
        load_rules(write(tmp_path, GOOD.replace("title     =", 'titel     = "x"\ntitle     =', 1)))


def test_rejects_review_rule_with_a_tool_rule_name(tmp_path):
    bad = GOOD.replace('tool = "review"', 'tool = "review"\nrule = "something"')
    with pytest.raises(RulesError, match="meaningless for tool='review'"):
        load_rules(write(tmp_path, bad))


def test_renderers_emit_every_rule(tmp_path):
    rules = load_rules(write(tmp_path, GOOD))
    for text in (render_html(rules), render_markdown_compact(rules), render_markdown_full(rules)):
        for r in rules:
            assert r.id in text
    assert render_html(rules).count('class="rule"') == 3
    assert render_markdown_full(rules).count("**Why:**") == 3


def test_html_escapes_example_snippets(tmp_path):
    """Examples are attacker-free but `<`, `>` and `&` are ordinary SV; they must escape."""
    toml = GOOD.replace(
        'good      = "input logic clk_i,  // System clock"',
        'good      = "assign y = a & (b < c);  // </pre><script>x</script>"',
    )
    html = render_html(load_rules(write(tmp_path, toml)))
    assert "&amp;" in html and "&lt;" in html
    assert "<script>x</script>" not in html


MULTI = """
[[rule]]
id        = "FMT-001"
title     = "The formatter owns whitespace"
severity  = "MUST"
category  = "FMT"
statement = "Indentation, trailing space and the final newline are the formatter's output."
rationale = "One rationale covers the whole mechanical family; nobody reviews them apart."
sources   = ["house style"]
[rule.enforcement]
tool = "verible-lint"
rule = ["no-tabs", "no-trailing-spaces", "posix-eof"]
"""


def test_one_rule_may_claim_several_tool_rules(tmp_path):
    (rule,) = load_rules(write(tmp_path, MULTI))
    assert rule.tool_rules == ("no-tabs", "no-trailing-spaces", "posix-eof")
    index = tool_index([rule], "verible-lint")
    assert set(index) == {"no-tabs", "no-trailing-spaces", "posix-eof"}
    assert index["posix-eof"].id == "FMT-001"
    assert "no-tabs" in render_markdown_full([rule])


def test_rejects_a_repeated_name_within_one_rule(tmp_path):
    bad = MULTI.replace('"no-trailing-spaces"', '"no-tabs"')
    with pytest.raises(RulesError, match="repeats a name"):
        load_rules(write(tmp_path, bad))


def test_rejects_two_rules_claiming_the_same_tool_rule(tmp_path):
    second = MULTI.replace('id        = "FMT-001"', 'id        = "FMT-002"')
    second = second.replace(
        'rule = ["no-tabs", "no-trailing-spaces", "posix-eof"]', 'rule = "no-tabs"'
    )
    with pytest.raises(RulesError, match="already claimed by FMT-001"):
        load_rules(write(tmp_path, MULTI + second))


ALSO = MULTI + '[rule.also]\nverilator = ["WIDTHTRUNC", "WIDTHEXPAND"]\n'


def test_a_rule_may_name_secondary_enforcers(tmp_path):
    (rule,) = load_rules(write(tmp_path, ALSO))
    assert rule.also == (("verilator", ("WIDTHTRUNC", "WIDTHEXPAND")),)
    assert tool_index([rule], "verilator")["WIDTHEXPAND"].id == "FMT-001"
    assert "`WIDTHTRUNC`" in render_markdown_full([rule])
    assert "WIDTHTRUNC" in render_html([rule])


@pytest.mark.parametrize(
    "also,message",
    [
        ('review = ["X"]', "also: tool must be one of"),
        ('clang = ["X"]', "also: tool must be one of"),
        ("verilator = []", "also.verilator must be a name or a list of names"),
    ],
)
def test_rejects_malformed_also(tmp_path, also, message):
    with pytest.raises(RulesError, match=message):
        load_rules(write(tmp_path, MULTI + f"[rule.also]\n{also}\n"))


def test_also_names_are_claimed_like_primary_ones(tmp_path):
    second = MULTI.replace('id        = "FMT-001"', 'id        = "FMT-002"').replace(
        'tool = "verible-lint"\nrule = ["no-tabs", "no-trailing-spaces", "posix-eof"]',
        'tool = "verilator"\nrule = "WIDTHTRUNC"',
    )
    with pytest.raises(RulesError, match="already claimed by FMT-001"):
        load_rules(write(tmp_path, ALSO + second))


def test_the_shipped_verible_config_parses_to_61_rules():
    """The config is a delta on Verible's default ruleset, so it lists every rule."""
    from svstyle.cli import VERIBLE_LINT_CONFIG

    enabled, disabled = set(), set()
    for line in VERIBLE_LINT_CONFIG.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        (disabled if line.startswith("-") else enabled).add(line.lstrip("+-").split("=", 1)[0])
    assert len(enabled) == 52
    assert len(disabled) == 9
    assert not (enabled & disabled)


# --- the shipped database ---------------------------------------------------


def test_shipped_rules_load_and_cover_every_enabled_verible_rule():
    from svstyle.cli import VERIBLE_LINT_CONFIG

    rules = load_rules()
    assert len(rules) >= 60, "the guide is meant to be comprehensive"

    enabled = set()
    for line in VERIBLE_LINT_CONFIG.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith(("#", "-")):
            enabled.add(line.lstrip("+").split("=", 1)[0])
    claimed = set(tool_index(rules, "verible-lint"))
    assert claimed == enabled, f"unclaimed: {enabled - claimed}; phantom: {claimed - enabled}"


def test_shipped_rules_have_no_drift(capsys):
    """This is the CI gate: DB, configs, generated docs and code must agree."""
    from svstyle.cli import _check

    assert _check(load_rules()) == 0, capsys.readouterr().err


def test_every_rule_carries_a_rationale_and_a_source():
    for r in load_rules():
        assert len(r.rationale) > 60, f"{r.id}: rationale too thin to review"
        assert r.sources, f"{r.id}: no source"
        assert r.good and r.bad, f"{r.id}: needs both a good and a bad example"


def test_full_markdown_opens_with_a_contents_list():
    text = render_markdown_full(load_rules())
    contents = text[: text.index("\n## DOC")]
    assert "- DOC — Comments and file header: DOC-001 … DOC-010" in contents
