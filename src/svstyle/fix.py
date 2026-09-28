"""`svstyle fix`: insert-only rewriting, guarded by the token-signature invariant.

    parse (refuse on error) -> Verible -> checks -> apply inserts -> Verible
    -> assert tokens unchanged and output parses

Never rebuilds the file from the tree: the only edits are Verible's whitespace
and svstyle's inserted comments and directives, so nothing the author wrote
can be lost.
"""

from collections.abc import Sequence

from pyslang import BumpAllocator, Diagnostics, SourceManager
from pyslang.parsing import Lexer, TokenKind

from .checks import PLACEHOLDER, run_checks
from .external import verible_format
from .parse import ParseError, parse
from .rules import Rule

NETTYPE = "`default_nettype none"
RESETALL = "`resetall"


class InvariantError(Exception):
    """svstyle produced output it cannot vouch for; nothing is written (exit 4)."""


def token_signature(text: str) -> list[str]:
    """Every token of `text` except whitespace and comments.

    Uses the raw lexer, not the preprocessor, so directives and `ifdef`-disabled
    text are part of the signature: a fix that touches them is caught too.
    """
    sm = SourceManager()
    lexer = Lexer(sm.assignText("sig.sv", text), BumpAllocator(), Diagnostics(), sm)
    out = []
    while (tok := lexer.lex()).kind != TokenKind.EndOfFile:
        out.append(tok.rawText)
    return out


def fix_text(
    text: str,
    path: str,
    rules: list[Rule],
    include_dirs: Sequence[str] = (),
    company: str = PLACEHOLDER,
) -> str:
    parse(text, path, include_dirs)  # ParseError propagates: refuse before touching anything
    formatted = verible_format(text)
    fixes = [d.fix for d in run_checks(formatted, path, rules, include_dirs, company) if d.fix]
    out = formatted
    # Descending offset; at equal offsets the later fix goes in first, so the
    # earlier one (the header) ends up above it.
    for _, (off, ins, *cut) in sorted(
        enumerate(fixes), key=lambda f: (f[1][0], f[0]), reverse=True
    ):
        out = out[:off] + ins + out[off + (cut[0] if cut else 0) :]
    out = verible_format(out)

    sig = token_signature(out)
    inserted = "".join(f[1] for f in fixes)
    if NETTYPE in inserted:
        i = sig.index("`default_nettype")
        del sig[i : i + 2]
    if RESETALL in inserted:
        del sig[len(sig) - 1 - sig[::-1].index(RESETALL)]
    if sig != token_signature(text):
        raise InvariantError(f"{path}: fix changed a non-whitespace token")
    try:
        parse(out, path, include_dirs)
    except ParseError as e:
        raise InvariantError(f"{path}: fixed output no longer parses\n{e}") from e
    return out
