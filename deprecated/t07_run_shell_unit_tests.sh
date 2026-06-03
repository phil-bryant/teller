#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
#R001: Run from repository root regardless of caller cwd.
cd "$REPO_ROOT"

#R005: Execute only the shell unit-test lane.
if RUN_SHELL_TESTS=true \
  RUN_PYTHON_TESTS=false \
  RUN_SQL_TESTS=false \
  RUN_SWIFT_TESTS=false \
  RUN_MACOS_UI_REGRESSION_TESTS=false \
  BATS_JOBS=1 \
  "${REPO_ROOT}/src/scripts/run_unit_test_lanes.sh"; then
  #R006: Emit an unambiguous success marker at completion.
  echo "✅ Shell unit tests succeeded."
else
  #R006: Emit an unambiguous failure marker at completion.
  echo "❌ Shell unit tests failed."
  exit 1
fi
