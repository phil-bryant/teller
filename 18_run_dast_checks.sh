#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./.security-venv}"
BASE_HOST="${DAST_BASE_HOST:-127.0.0.1}"
BASE_PORT="${DAST_BASE_PORT:-8787}"
BASE_URL="${DAST_BASE_URL:-http://${BASE_HOST}:${BASE_PORT}}"
OPENAPI_URL="${DAST_OPENAPI_URL:-${BASE_URL}/openapi.json}"

RUN_SCHEMATHESIS="${RUN_SCHEMATHESIS:-true}"
RUN_ZAP="${RUN_ZAP:-true}"
RUN_TOKEN_CAPTURE_DAST="${RUN_TOKEN_CAPTURE_DAST:-auto}" # true|false|auto
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
ZAP_BASELINE_CMD="${ZAP_BASELINE_CMD:-zap-baseline.py}"

TOKEN_CAPTURE_PORT="${TOKEN_CAPTURE_DAST_PORT:-8088}"
TOKEN_CAPTURE_URL="${TOKEN_CAPTURE_DAST_URL:-http://127.0.0.1:${TOKEN_CAPTURE_PORT}}"
DAST_APP_PYTHON="${DAST_APP_PYTHON:-./teller-venv/bin/python}"

SCHEMATHESIS_SEED="${SCHEMATHESIS_SEED:-424242}"
SCHEMATHESIS_MAX_EXAMPLES="${SCHEMATHESIS_MAX_EXAMPLES:-25}"

mkdir -p "$REPORT_DIR"

if [[ -d "$SECURITY_VENV_DIR/bin" ]]; then
  export PATH="${SECURITY_VENV_DIR}/bin:${PATH}"
fi

if [[ ! -x "$DAST_APP_PYTHON" ]]; then
  DAST_APP_PYTHON="python3"
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    exit 1
  fi
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      echo "❌ Timed out waiting for ${url}"
      return 1
    fi
    sleep 1
  done
}

run_zap_baseline() {
  local target_url="$1"
  local json_report="$2"
  local html_report="$3"
  local log_report="$4"
  echo "▶ Running OWASP ZAP Baseline against ${target_url}"
  "$ZAP_BASELINE_CMD" \
    -t "$target_url" \
    -J "$json_report" \
    -r "$html_report" \
    -m 3 \
    -c ".zap/rules.tsv" \
    -I | tee "$log_report"
}

CLASSIFIER_API_PID=""
TOKEN_CAPTURE_PID=""

cleanup() {
  if [[ -n "$TOKEN_CAPTURE_PID" ]] && kill -0 "$TOKEN_CAPTURE_PID" >/dev/null 2>&1; then
    kill "$TOKEN_CAPTURE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$CLASSIFIER_API_PID" ]] && kill -0 "$CLASSIFIER_API_PID" >/dev/null 2>&1; then
    kill "$CLASSIFIER_API_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "▶ Starting local classification API for DAST at ${BASE_URL}"
TELLER_CLASSIFIER_API_HOST="$BASE_HOST" TELLER_CLASSIFIER_API_PORT="$BASE_PORT" \
  "$DAST_APP_PYTHON" "./14_run_classification_api.py" >"${REPORT_DIR}/classification-api.log" 2>&1 &
CLASSIFIER_API_PID="$!"
wait_for_http "${BASE_URL}/health" 45

if [[ "$RUN_SCHEMATHESIS" == "true" ]]; then
  require_command schemathesis
  echo "▶ Running Schemathesis against ${OPENAPI_URL}"
  schemathesis run "$OPENAPI_URL" \
    --url "$BASE_URL" \
    --seed "$SCHEMATHESIS_SEED" \
    --max-examples "$SCHEMATHESIS_MAX_EXAMPLES" \
    --report junit \
    --report-junit-path "${REPORT_DIR}/schemathesis-junit.xml" \
    | tee "${REPORT_DIR}/schemathesis.log"
fi

if [[ "$RUN_ZAP" == "true" ]]; then
  require_command "$ZAP_BASELINE_CMD"
  run_zap_baseline \
    "$BASE_URL" \
    "${REPORT_DIR}/zap-classification.json" \
    "${REPORT_DIR}/zap-classification.html" \
    "${REPORT_DIR}/zap-classification.log"
fi

if [[ "$RUN_TOKEN_CAPTURE_DAST" == "auto" ]]; then
  if [[ -f "$HOME/.teller/application_id.txt" ]]; then
    RUN_TOKEN_CAPTURE_DAST="true"
  else
    RUN_TOKEN_CAPTURE_DAST="false"
  fi
fi

if [[ "$RUN_TOKEN_CAPTURE_DAST" == "true" ]]; then
  echo "▶ Starting token capture server for DAST at ${TOKEN_CAPTURE_URL}"
  "$DAST_APP_PYTHON" "./teller/teller_connect_token_server.py" --no-open --mode manage --port "$TOKEN_CAPTURE_PORT" \
    >"${REPORT_DIR}/token-capture.log" 2>&1 &
  TOKEN_CAPTURE_PID="$!"
  wait_for_http "${TOKEN_CAPTURE_URL}/api/status" 45

  if [[ "$RUN_ZAP" == "true" ]]; then
    run_zap_baseline \
      "$TOKEN_CAPTURE_URL" \
      "${REPORT_DIR}/zap-token-capture.json" \
      "${REPORT_DIR}/zap-token-capture.html" \
      "${REPORT_DIR}/zap-token-capture.log"
  fi
else
  echo "ℹ️  Token capture DAST skipped (set RUN_TOKEN_CAPTURE_DAST=true and ensure ~/.teller/application_id.txt exists)."
fi

HIGH_ALERTS=0
for zap_json in "${REPORT_DIR}/zap-classification.json" "${REPORT_DIR}/zap-token-capture.json"; do
  if [[ -f "$zap_json" ]]; then
    alerts="$(python3 - <<'PY' "$zap_json"
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
sites = payload.get("site", []) if isinstance(payload, dict) else []
count = 0
for site in sites:
    for alert in site.get("alerts", []):
        try:
            risk = int(alert.get("riskcode", "-1"))
        except ValueError:
            risk = -1
        if risk >= 3:
            count += 1
print(count)
PY
)"
    HIGH_ALERTS=$((HIGH_ALERTS + alerts))
  fi
done

echo "DAST high/critical alert count: ${HIGH_ALERTS}"
if [[ "$FAIL_ON_HIGH_CRITICAL" == "true" ]] && (( HIGH_ALERTS > 0 )); then
  echo "❌ DAST gate failed: High/Critical ZAP alerts detected."
  exit 1
fi

echo "✅ DAST checks completed."
