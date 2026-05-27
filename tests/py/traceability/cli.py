#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from .verification import TraceabilityVerifier


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    repo_root = Path.cwd()
    verifier = TraceabilityVerifier(repo_root=repo_root)
    return verifier.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
