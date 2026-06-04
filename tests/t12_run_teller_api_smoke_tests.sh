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

REPORT_DIR="${TELLER_SMOKE_REPORT_DIR:-./artifacts/security}"
TELLER_TIMEOUT_SECONDS="${TELLER_SMOKE_TIMEOUT_SECONDS:-15}"
TELLER_INSTITUTION_ID="${TELLER_SMOKE_INSTITUTION_ID:-}"

mkdir -p "$REPORT_DIR"

PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"
PROJECT_PYTHON_EXPLICIT=false
if [[ -n "${DEPENDENCY_CHECK_PYTHON:-}" ]]; then
  PROJECT_PYTHON_EXPLICIT=true
fi
if [[ -z "$PROJECT_PYTHON" ]]; then
  #R005: Prefer active virtualenv interpreter, then local teller-venv, then system python.
  if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ -x "${VIRTUAL_ENV}/bin/python" ]]; then
    PROJECT_PYTHON="${VIRTUAL_ENV}/bin/python"
  elif [[ -x "./teller-venv/bin/python" ]]; then
    PROJECT_PYTHON="./teller-venv/bin/python"
  else
    PROJECT_PYTHON="python3"
  fi
fi

if [[ ! -x "$PROJECT_PYTHON" ]] && [[ "$PROJECT_PYTHON" != "python3" ]]; then
  echo "❌ Project python not executable: $PROJECT_PYTHON"
  exit 1
fi

if [[ "$PROJECT_PYTHON_EXPLICIT" != "true" ]]; then
  if ! "$PROJECT_PYTHON" -c "import site" >/dev/null 2>&1; then
    echo "⚠️ Selected interpreter '$PROJECT_PYTHON' is not usable; falling back to python3"
    PROJECT_PYTHON="python3"
  fi
fi

echo "ℹ️ Teller auth mode: use TELLER_ACCESS_TOKEN when set, otherwise discover local ~/.teller tokens."
#R010: Run Teller API smoke checks and emit JSON/text report artifacts.
echo "▶ Running Teller API smoke checks with ${PROJECT_PYTHON}"
TELLER_SMOKE_ARGS=(
  ./src/scripts/check_teller_api_drift.py
  --run-all-tokens
  --timeout-seconds "${TELLER_TIMEOUT_SECONDS}"
  --output-json "${REPORT_DIR}/teller-api-smoke.json"
  --output-text "${REPORT_DIR}/teller-api-smoke.txt"
)
if [[ -n "$TELLER_INSTITUTION_ID" ]]; then
  TELLER_SMOKE_ARGS+=(--institution-id "${TELLER_INSTITUTION_ID}")
fi
"$PROJECT_PYTHON" "${TELLER_SMOKE_ARGS[@]}"

echo "✅ Teller API smoke checks completed. Reports: ${REPORT_DIR}"
