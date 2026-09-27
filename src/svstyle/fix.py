"""`svstyle fix`: insert-only rewriting, guarded by the token-signature invariant."""

from pyslang import BumpAllocator, Diagnostics, SourceManager
from pyslang.parsing import Lexer, TokenKind


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
