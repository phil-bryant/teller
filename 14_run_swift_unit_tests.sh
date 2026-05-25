#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Run from repository root regardless of caller cwd.
cd "$SCRIPT_DIR"

#R005: Execute only the Swift unit-test lane.
RUN_SHELL_TESTS=false \
RUN_PYTHON_TESTS=false \
RUN_SQL_TESTS=false \
RUN_SWIFT_TESTS=true \
RUN_MACOS_UI_REGRESSION_TESTS=false \
  "${SCRIPT_DIR}/src/scripts/run_unit_test_lanes.sh"
