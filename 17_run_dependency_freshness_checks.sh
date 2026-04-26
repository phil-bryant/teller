#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./.security-reports}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./.security-venv}"
RUN_PIP_AUDIT="${RUN_PIP_AUDIT:-true}"
RUN_TELLER_CANARY="${RUN_TELLER_CANARY:-true}"
FAIL_ON_MAJOR="${DEPENDENCY_FAIL_ON_MAJOR:-false}"

mkdir -p "$REPORT_DIR"

PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"
if [[ -z "$PROJECT_PYTHON" ]]; then
  if [[ -x "./teller-venv/bin/python" ]]; then
    PROJECT_PYTHON="./teller-venv/bin/python"
  else
    PROJECT_PYTHON="python3"
  fi
fi

if [[ ! -x "$PROJECT_PYTHON" ]] && [[ "$PROJECT_PYTHON" != "python3" ]]; then
  echo "❌ Project python not executable: $PROJECT_PYTHON"
  exit 1
fi

ensure_security_venv() {
  if [[ ! -d "$SECURITY_VENV_DIR" ]]; then
    echo "▶ Creating isolated security virtualenv at ${SECURITY_VENV_DIR}"
    python3 -m venv "$SECURITY_VENV_DIR"
  fi
  local security_pip="${SECURITY_VENV_DIR}/bin/pip"
  if [[ ! -x "${SECURITY_VENV_DIR}/bin/pip-audit" ]]; then
    echo "▶ Installing pip-audit into ${SECURITY_VENV_DIR}"
    "$security_pip" install --upgrade pip
    "$security_pip" install pip-audit
  fi
}

echo "▶ Running dependency freshness checks with ${PROJECT_PYTHON}"
if [[ "$FAIL_ON_MAJOR" == "true" ]]; then
  "$PROJECT_PYTHON" ./scripts/check_dependency_freshness.py \
    --output-json "${REPORT_DIR}/dependency-freshness.json" \
    --output-text "${REPORT_DIR}/dependency-freshness.txt" \
    --fail-on-major
else
  "$PROJECT_PYTHON" ./scripts/check_dependency_freshness.py \
    --output-json "${REPORT_DIR}/dependency-freshness.json" \
    --output-text "${REPORT_DIR}/dependency-freshness.txt"
fi

if [[ "$RUN_PIP_AUDIT" == "true" ]]; then
  ensure_security_venv
  export PIPAPI_PYTHON_LOCATION="$PROJECT_PYTHON"
  echo "▶ Running pip-audit against ${PIPAPI_PYTHON_LOCATION}"
  set +e
  "${SECURITY_VENV_DIR}/bin/pip-audit" --format json --output "${REPORT_DIR}/pip-audit.json"
  status=$?
  set -e
  if [[ "$status" -gt 1 ]]; then
    echo "❌ pip-audit execution failed."
    exit 1
  fi
fi

if [[ "$RUN_TELLER_CANARY" == "true" ]]; then
  echo "▶ Running Teller API drift checks"
  "$PROJECT_PYTHON" ./scripts/check_teller_api_drift.py \
    --output-json "${REPORT_DIR}/teller-api-drift.json" \
    --output-text "${REPORT_DIR}/teller-api-drift.txt"
fi

echo "✅ Dependency freshness checks completed. Reports: ${REPORT_DIR}"
