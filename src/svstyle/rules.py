"""The rules database: load `rules.toml` and validate it.

`rules.toml` is the single source of truth. Everything else -- the HTML review
page, the skill's reference files, the checker's rule IDs -- is derived from it,
so a malformed entry has to fail loudly here rather than propagate.
"""

import re
import tomllib
from dataclasses import dataclass, fields
from pathlib import Path

RULES_TOML = Path(__file__).with_name("rules.toml")

ID_RE = re.compile(r"^[A-Z]{3}-\d{3}$")

# Category prefix -> human title, in the order the docs present them.
CATEGORIES = {
    "DOC": "Comments and file header",
    "STR": "File structure",
    "PRT": "Ports and connections",
    "NAM": "Naming",
    "FMT": "Formatting and layout",
    "LNG": "Language features",
    "SYN": "Synthesis and portability",
    "RST": "Reset and clocking",
    "FSM": "State machines",
    "CDC": "Clock domain crossing",
    "GEN": "Generate and parameterisation",
    "VER": "Assertions and verification",
}

SEVERITIES = ("MUST", "SHOULD", "MAY")

# Who enforces a rule. `review` means no tool can: the skill and a human carry it.
TOOLS = ("verible-format", "verible-lint", "verilator", "yosys", "svstyle", "review")
# Tools that report diagnostics by name, so can back up a rule another tool owns.
ALSO_TOOLS = ("verible-lint", "verilator", "yosys", "svstyle")

_REQUIRED = ("id", "title", "severity", "category", "statement", "rationale", "sources")


class RulesError(Exception):
    """rules.toml is malformed. The message names the offending rule."""


@dataclass(frozen=True)
class Rule:
    id: str
    title: str
    severity: str
    category: str
    statement: str
    rationale: str
    sources: tuple[str, ...]
    tool: str
    # Tool-side rule names / warning codes this rule subsumes. Several because one
    # house rule with one rationale often covers a family of mechanical tool rules
    # (`no-tabs`, `no-trailing-spaces`, `posix-eof` are all "the formatter owns
    # whitespace"). Empty for `review`.
    tool_rules: tuple[str, ...]
    autofix: bool
    good: str = ""
    bad: str = ""
    # Secondary enforcers from `[rule.also]`: another tool that reports the same
    # rule under its own names (LNG-007 is Verible `case-missing-default` and
    # Verilator CASEINCOMPLETE). They map diagnostics; `tool` stays the owner.
    also: tuple[tuple[str, tuple[str, ...]], ...] = ()

    @property
    def number(self) -> int:
        return int(self.id[4:])


@dataclass(frozen=True)
class Diag:
    """One finding, from svstyle's own checks or translated from an external tool."""

    path: str
    line: int
    col: int
    rule: str  # house rule ID, or EXT-VL-<name> / EXT-VLTR-<CODE> when unmapped
    severity: str
    message: str
    fixable: bool = False
    # (offset, text) to insert, or (offset, text, n) to replace n chars; own checks only
    fix: tuple | None = None


def _rule_from_toml(raw: dict, index: int) -> Rule:
    where = raw.get("id") or f"rule #{index + 1}"
    missing = [k for k in _REQUIRED if not raw.get(k)]
    if missing:
        raise RulesError(f"{where}: missing or empty {', '.join(missing)}")

    known = {f.name for f in fields(Rule)} - {"tool", "tool_rules", "autofix"}
    unknown = set(raw) - known - {"enforcement"}
    if unknown:
        raise RulesError(f"{where}: unknown key(s) {', '.join(sorted(unknown))}")

    rid = raw["id"]
    if not ID_RE.match(rid):
        raise RulesError(f"{where}: id must look like NAM-001")
    if rid[:3] not in CATEGORIES:
        raise RulesError(f"{rid}: unknown category prefix (have {', '.join(CATEGORIES)})")
    if rid[:3] != raw["category"]:
        raise RulesError(f"{rid}: category {raw['category']!r} disagrees with the id prefix")
    if raw["severity"] not in SEVERITIES:
        raise RulesError(f"{rid}: severity must be one of {', '.join(SEVERITIES)}")

    enf = raw.get("enforcement") or {}
    tool = enf.get("tool")
    if tool not in TOOLS:
        raise RulesError(f"{rid}: enforcement.tool must be one of {', '.join(TOOLS)}")
    tool_rules = _names(enf.get("rule", ()), f"{rid}: enforcement.rule")
    also = []
    for t, names in (raw.get("also") or {}).items():
        if t not in ALSO_TOOLS:
            raise RulesError(f"{rid}: also: tool must be one of {', '.join(ALSO_TOOLS)}")
        also.append((t, _names(names, f"{rid}: also.{t}")))
        if not also[-1][1]:
            raise RulesError(f"{rid}: also.{t} must be a name or a list of names")
    if tool == "review" and tool_rules:
        raise RulesError(f"{rid}: enforcement.rule is meaningless for tool='review'")
    if tool not in ("review", "verible-format") and not tool_rules:
        raise RulesError(f"{rid}: enforcement.rule is required for tool={tool!r}")
    autofix = bool(enf.get("autofix", False))
    if autofix and tool == "review":
        raise RulesError(f"{rid}: tool='review' cannot autofix")

    return Rule(
        id=rid,
        title=raw["title"],
        severity=raw["severity"],
        category=raw["category"],
        statement=raw["statement"].strip(),
        rationale=raw["rationale"].strip(),
        sources=tuple(raw["sources"]),
        tool=tool,
        tool_rules=tool_rules,
        autofix=autofix,
        good=raw.get("good", "").strip("\n"),
        bad=raw.get("bad", "").strip("\n"),
        also=tuple(also),
    )


def _names(raw, where: str) -> tuple[str, ...]:
    if isinstance(raw, str):
        raw = (raw,) if raw else ()
    if not isinstance(raw, list | tuple) or not all(isinstance(n, str) and n for n in raw):
        raise RulesError(f"{where} must be a name or a list of names")
    if len(set(raw)) != len(raw):
        raise RulesError(f"{where} repeats a name")
    return tuple(raw)


def claims(rule: Rule) -> list[tuple[str, str]]:
    """Every (tool, tool-side name) this rule answers for, owner first."""
    return [(rule.tool, n) for n in rule.tool_rules] + [
        (t, n) for t, names in rule.also for n in names
    ]


def load_rules(path: Path | None = None) -> list[Rule]:
    """Parse and validate the rules DB. Sorted by category order, then number."""
    path = path or RULES_TOML
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise RulesError(f"{path}: {exc}") from exc

    rules = [_rule_from_toml(raw, i) for i, raw in enumerate(data.get("rule", []))]
    if not rules:
        raise RulesError(f"{path}: no [[rule]] entries")

    seen: dict[str, int] = {}
    for i, rule in enumerate(rules):
        if rule.id in seen:
            raise RulesError(f"{rule.id}: duplicate id (also entry #{seen[rule.id] + 1})")
        seen[rule.id] = i

    # Two house rules claiming the same tool rule would make the diagnostic
    # mapping ambiguous and silently hide one of them.
    claimed: dict[tuple[str, str], str] = {}
    for rule in rules:
        for key in claims(rule):
            if key in claimed:
                raise RulesError(
                    f"{rule.id}: {key[0]} rule {key[1]!r} is already claimed by {claimed[key]}"
                )
            claimed[key] = rule.id

    order = list(CATEGORIES)
    return sorted(rules, key=lambda r: (order.index(r.category), r.number))


def by_category(rules: list[Rule]) -> dict[str, list[Rule]]:
    """Rules grouped by category, in CATEGORIES order, empty categories dropped."""
    out: dict[str, list[Rule]] = {}
    for rule in rules:
        out.setdefault(rule.category, []).append(rule)
    return {c: out[c] for c in CATEGORIES if c in out}


def keep_rule(rule: str, select: str | None, ignore: str | None) -> bool:
    """ruff-style prefixes: `--select DOC,PRT-001 --ignore DOC-005`."""
    if select and not rule.startswith(tuple(select.split(","))):
        return False
    return not (ignore and rule.startswith(tuple(ignore.split(","))))


def tool_index(rules: list[Rule], tool: str) -> dict[str, Rule]:
    """Map a tool's own rule name / warning code back to our rule.

    Used to translate Verible and Verilator diagnostics into house rule IDs.
    """
    return {name: r for r in rules for t, name in claims(r) if t == tool}
