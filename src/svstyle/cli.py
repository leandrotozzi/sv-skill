"""Command-line entry point. Real subcommands land in Phase 2."""

import sys

from . import __version__


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] in ("--version", "-V"):
        print(f"svstyle {__version__}")
        return 0
    print(f"svstyle {__version__}: check/fix/rules not implemented yet (Phase 2)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
