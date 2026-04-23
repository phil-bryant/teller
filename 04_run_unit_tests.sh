#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Run tests from repository root regardless of caller working directory.
cd "$SCRIPT_DIR"

#R005: Prefer project venv when available.
if [[ -d "./teller-venv" ]]; then
  # shellcheck disable=SC1091
  source "./teller-venv/bin/activate"
fi

#R010 #R015: Discover all unittest modules and propagate failures.
python3 -m unittest discover tests
