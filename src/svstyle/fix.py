"""`svstyle fix`: targeted edits, guarded by the token-edit invariant.

    parse (refuse on error) -> Verible -> checks + rewrites -> apply -> Verible
    -> assert every token change is on the whitelist and output parses

Never rebuilds the file from the tree. The edits are Verible's whitespace,
svstyle's inserted comments and directives, and a short whitelist of token
rewrites that modernise legacy code without changing what it means
(`reg` -> `logic`, `always @(*)` -> `always_comb`, begin/end around a lone
statement, ...). Which occurrences are safe to rewrite is decided in parse.py
from the syntax tree; the invariant here makes sure nothing else changed.
"""

import difflib
from collections.abc import Sequence
from functools import cache

from .checks import PLACEHOLDER, run_checks
from .external import verible_format
from .parse import DIRECTIVE_LINE_RE, ParseError, parse, raw_tokens
from .rules import Rule

# (tokens before, tokens after) for every token edit a fix may make.
ALLOWED_EDITS = (
    ((), ("`default_nettype", "none")),
    ((), ("`resetall",)),
    (("reg",), ("logic",)),
    (("wire",), ("logic",)),
    (("always", "@", "(", "*", ")"), ("always_comb",)),
    (("always", "@", "*"), ("always_comb",)),
    (("always",), ("always_ff",)),
    ((), ("begin",)),
    ((), ("end",)),
    (("generate",), ()),
    (("endgenerate",), ()),
    ((), ("automatic",)),
)

MAX_PASSES = 4  # each pass only adds structure; real code settles in two
INSERTED = frozenset(tok for old, new in ALLOWED_EDITS if not old for tok in new)


class InvariantError(Exception):
    """svstyle produced output it cannot vouch for; nothing is written (exit 4)."""


def token_signature(text: str) -> list[str]:
    """Every token of `text` except whitespace and comments.

    Uses the raw lexer, not the preprocessor, so directives and `ifdef`-disabled
    text are part of the signature: a fix that touches them is caught too.
    """
    return [raw for _, raw, _ in raw_tokens(text)]


def allowed_edit(old: Sequence[str], new: Sequence[str]) -> bool:
    """Whether `old` -> `new` decomposes into kept tokens and ALLOWED_EDITS."""
    return _allowed(tuple(old), tuple(new))


@cache
def _allowed(old: tuple, new: tuple) -> bool:
    if not old and not new:
        return True
    if old and new and old[0] == new[0] and _allowed(old[1:], new[1:]):
        return True
    return any(
        old[: len(a)] == a and new[: len(b)] == b and _allowed(old[len(a) :], new[len(b) :])
        for a, b in ALLOWED_EDITS
    )


def endif_labels(text: str) -> list[tuple[int, str, int]]:
    """DOC-010: `// NAME` after every unlabelled `endif closing `ifdef NAME."""
    stack: list[str] = []
    out, off = [], 0
    for ln in text.splitlines(keepends=True):
        if m := DIRECTIVE_LINE_RE.match(ln):
            kw, name, rest = m.groups()
            if kw in ("ifdef", "ifndef"):
                stack.append(name)
            elif kw == "endif" and stack:
                opened = stack.pop()
                if opened and not rest.strip():
                    out.append((off + len(ln.rstrip("\r\n")), f"  // {opened}", 0))
        off += len(ln)
    return out


def fix_text(
    text: str,
    path: str,
    rules: list[Rule],
    include_dirs: Sequence[str] = (),
    company: str = PLACEHOLDER,
) -> str:
    parse(text, path, include_dirs)  # ParseError propagates: refuse before touching anything
    # A rewrite can create what another rule anchors on (`always @(*)` becomes an
    # always_comb that DOC-005 wants a comment above), so rerun until tokens settle.
    for _ in range(MAX_PASSES):
        out = _fix_once(text, path, rules, include_dirs, company)
        if token_signature(out) == token_signature(text):
            return out
        text = out
    raise InvariantError(f"{path}: fix did not settle after {MAX_PASSES} passes")


def _fix_once(
    text: str, path: str, rules: list[Rule], include_dirs: Sequence[str], company: str
) -> str:
    formatted = verible_format(text)
    found = [d.fix for d in run_checks(formatted, path, rules, include_dirs, company) if d.fix]
    fixes = [f for fix in found for f in (fix if isinstance(fix, list) else [fix])]
    fixes += parse(formatted, path, include_dirs).rewrites + endif_labels(formatted)
    fixes = [(off, ins, cut[0] if cut else 0) for off, ins, *cut in fixes]
    out = formatted
    # Descending offset. At one offset a replacement goes first, so an insertion
    # there lands in front of the new text instead of being cut by it; between
    # insertions the later fix goes in first, so the earlier (the header) ends up above.
    for _, (off, ins, cut) in sorted(
        enumerate(fixes), key=lambda f: (f[1][0], f[1][2] > 0, f[0]), reverse=True
    ):
        out = out[:off] + ins + out[off + cut :]
    out = verible_format(out)

    before, after = token_signature(text), token_signature(out)
    # Tokens fixes only ever insert are junk to the matcher: anchored on them, a
    # repeated statement aligns with the wrong copy and a legal edit looks illegal.
    matcher = difflib.SequenceMatcher(INSERTED.__contains__, before, after, autojunk=False)
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op != "equal" and not allowed_edit(before[i1:i2], after[j1:j2]):
            got = " ".join(after[j1:j2]) or "nothing"
            raise InvariantError(
                f"{path}: fix changed tokens `{' '.join(before[i1:i2])}` into `{got}`"
            )
    try:
        parse(out, path, include_dirs)
    except ParseError as e:
        raise InvariantError(f"{path}: fixed output no longer parses\n{e}") from e
    return out
