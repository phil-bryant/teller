#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Resolve repo root from script path for deterministic relative references.
cd "$SCRIPT_DIR"

REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./.security-reports}"
RUN_TELLER_CANARY="${RUN_TELLER_CANARY:-true}"
FAIL_ON_MAJOR="${DEPENDENCY_FAIL_ON_MAJOR:-false}"

mkdir -p "$REPORT_DIR"

PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"
#R005: Prefer active virtualenv interpreter, then local teller-venv, then system python.
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

echo "▶ Running dependency freshness checks with ${PROJECT_PYTHON}"
#R010: Emit machine-readable and text freshness reports with optional major-version gate.
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

if [[ "$RUN_TELLER_CANARY" == "true" ]]; then
  #R015: Run optional Teller API compatibility/drift canary checks.
  echo "▶ Running Teller API drift checks"
  "$PROJECT_PYTHON" ./scripts/check_teller_api_drift.py \
    --output-json "${REPORT_DIR}/teller-api-drift.json" \
    --output-text "${REPORT_DIR}/teller-api-drift.txt"
fi

echo "✅ Dependency freshness checks completed. Reports: ${REPORT_DIR}"
