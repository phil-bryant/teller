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

REPORT_DIR="${TELLER_LIVE_CANARY_REPORT_DIR:-./artifacts/security/live-canary}"
CANARY_TIMEOUT_SECONDS="${TELLER_LIVE_CANARY_TIMEOUT_SECONDS:-20}"
CANARY_INSTITUTION_ID="${TELLER_LIVE_CANARY_INSTITUTION_ID:-}"
RUN_ALL_TOKENS="${TELLER_LIVE_CANARY_RUN_ALL_TOKENS:-true}"
PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"

mkdir -p "$REPORT_DIR"

if [[ -z "$PROJECT_PYTHON" ]]; then
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

#R005: Enforce live-only canary semantics; fallback mode and warnings fail this lane.
CANARY_ARGS=(
  ./src/scripts/check_teller_api_drift.py
  --timeout-seconds "${CANARY_TIMEOUT_SECONDS}"
  --output-json "${REPORT_DIR}/teller-api-live-canary.json"
  --output-text "${REPORT_DIR}/teller-api-live-canary.txt"
  --require-live
  --fail-on-warn
)
if [[ "$RUN_ALL_TOKENS" == "true" ]]; then
  CANARY_ARGS+=(--run-all-tokens)
fi
if [[ -n "$CANARY_INSTITUTION_ID" ]]; then
  CANARY_ARGS+=(--institution-id "${CANARY_INSTITUTION_ID}")
fi

echo "▶ Running strict Teller live canary with ${PROJECT_PYTHON}"
"$PROJECT_PYTHON" "${CANARY_ARGS[@]}"
echo "✅ Strict Teller live canary completed. Reports: ${REPORT_DIR}"
