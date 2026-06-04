#!/usr/bin/env bash
# Self-contained teller test lane (relocated from the runner golden; teller-owned).
umask 007
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../../runner" && pwd -P)"
RUNBOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
export RUNBOOK_REPO_ROOT
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/teller.env"
# shellcheck source=/dev/null
source "${RUNNER_HOME}/src/scripts/runbook_common.sh"
REPO_ROOT="$RUNBOOK_REPO_ROOT"
cd "$REPO_ROOT"

#R005: Execute only the SQL unit-test lane.
RUN_SHELL_TESTS=false \
RUN_PYTHON_TESTS=false \
RUN_SQL_TESTS=true \
RUN_SWIFT_TESTS=false \
RUN_MACOS_UI_REGRESSION_TESTS=false \
  "${RUNNER_HOME}/src/scripts/run_unit_test_lanes.sh"
