#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Run tests from repository root regardless of caller working directory.
cd "$SCRIPT_DIR"

# Optional runner controls for local development.
RUN_SHELL_TESTS="${RUN_SHELL_TESTS:-true}"
RUN_PYTHON_TESTS="${RUN_PYTHON_TESTS:-true}"
RUN_SWIFT_TESTS="${RUN_SWIFT_TESTS:-true}"
RUN_MACOS_UI_REGRESSION_TESTS="${RUN_MACOS_UI_REGRESSION_TESTS:-false}"
BATS_FILTER="${BATS_FILTER:-}"

#R005: Prefer project venv when available.
if [[ -d "./teller-venv" ]]; then
  # shellcheck disable=SC1091
  source "./teller-venv/bin/activate"
fi

if [[ "$RUN_SHELL_TESTS" == "true" ]]; then
  if [[ -d "./tests/sh" ]]; then
    if ! command -v bats >/dev/null 2>&1; then
      echo "❌ bats is required for shell unit tests. Install bats-core and rerun."
      exit 1
    fi
    echo "▶ Running shell unit tests (bats)..."
    if [[ -n "$BATS_FILTER" ]]; then
      bats --filter "$BATS_FILTER" ./tests/sh
    else
      bats ./tests/sh
    fi
  else
    echo "ℹ️  Skipping shell unit tests: ./tests/sh not found."
  fi
fi

#R010 #R015: Discover all unittest modules and propagate failures.
if [[ "$RUN_PYTHON_TESTS" == "true" ]]; then
  echo "▶ Running Python unit tests (unittest)..."
  python3 -m unittest discover tests/py
fi

#R020 #R015: Run Swift package tests and propagate failures.
if [[ "$RUN_SWIFT_TESTS" == "true" ]]; then
  if [[ -d "./macos-ui/Tests" ]]; then
    if ! command -v swift >/dev/null 2>&1; then
      echo "❌ swift is required for Swift unit tests. Install Xcode command line tools and rerun."
      exit 1
    fi
    echo "▶ Running Swift unit tests (swift test)..."
    #R020: Clear stale SPM build cache to avoid module-cache path mismatches after folder renames.
    rm -rf ./macos-ui/.build
    swift test --package-path ./macos-ui
  else
    echo "ℹ️  Skipping Swift unit tests: ./macos-ui/Tests not found."
  fi
fi

if [[ "$RUN_MACOS_UI_REGRESSION_TESTS" == "true" ]]; then
  echo "▶ Running macOS UI regression test lane..."
  ./15_run_macos_ui_regression_tests.sh
fi
