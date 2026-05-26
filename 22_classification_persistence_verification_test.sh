#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R006: Support strict mode for CI to require explicit environment identifiers.
STRICT_IDS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-env-ids) STRICT_IDS=true; shift ;;
    --help)
      echo "Usage: TXN_ID=... CATEGORY_ID=... $0 [--require-env-ids]"
      echo "Default: auto-select missing TXN_ID/CATEGORY_ID from DB."
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

#R010: Resolve API and DB connection from the active profile (1psa+~/.env via the helper).
SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
DB_PROFILE_HELPER="${SCRIPT_DIR}/src/scripts/db_profile_export.sh"
PG_HOST=""
PG_PORT=""
PG_DBNAME=""
PG_USER=""
PG_SSLMODE="disable"
PG_ONEPSA_ITEM=""
if [[ ! -x "$DB_PROFILE_HELPER" ]]; then
  echo "❌ DB profile helper is missing or not executable: ${DB_PROFILE_HELPER}" >&2
  exit 1
fi
profile_exports_file="$(mktemp)"
if ! "$DB_PROFILE_HELPER" >"$profile_exports_file"; then
  #R040: Refuse persistence verification when DB profile setup is missing.
  rm -f "$profile_exports_file"
  exit 1
fi
PROFILE_EXPORTS="$(awk '/^(export )?[A-Za-z_][A-Za-z0-9_]*=/{sub(/^export /, ""); print}' "$profile_exports_file")"
rm -f "$profile_exports_file"
eval "$PROFILE_EXPORTS"

API_URL="${TELLER_CLASSIFIER_API_URL:-http://127.0.0.1:8787}"
API_SCHEME="$(python3 - <<'PY' "$API_URL"
import sys
from urllib.parse import urlparse
print((urlparse(sys.argv[1]).scheme or "http").lower())
PY
)"
DB_HOST="${TELLER_DB_HOST:-${PG_HOST:-localhost}}"
DB_PORT="${TELLER_DB_PORT:-${PG_PORT:-5432}}"
DB_NAME="${TELLER_DB_NAME:-${PG_DBNAME:-}}"
DB_USER="${TELLER_DB_USER:-${PG_USER:-teller}}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-}"

if [[ -z "$DB_NAME" ]]; then
  echo "❌ Resolved profile is missing PG_DBNAME and TELLER_DB_NAME is unset." >&2
  exit 1
fi

#R015: Resolve DB password from env or 1psa fallback.
if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-${PG_ONEPSA_ITEM:-localhost_postgres_teller}}")"
fi
WRITE_TOKEN="${TELLER_CLASSIFIER_WRITE_TOKEN:-}"
#R035: Resolve classifier write token from env when provided, otherwise use 1psa.
if [[ -z "$WRITE_TOKEN" ]]; then
  WRITE_TOKEN="$(1psa -p TELLER_CLASSIFIER_WRITE_TOKEN)"
fi
if [[ -z "$WRITE_TOKEN" ]]; then
  echo "Failed to read classifier write token from 1psa item: TELLER_CLASSIFIER_WRITE_TOKEN" >&2
  exit 1
fi

CLASSIFICATION_PERSISTENCE_START_API="${CLASSIFICATION_PERSISTENCE_START_API:-true}"
CLASSIFICATION_PERSISTENCE_API_PYTHON="${CLASSIFICATION_PERSISTENCE_API_PYTHON:-./teller-venv/bin/python}"
CLASSIFICATION_PERSISTENCE_API_STARTUP_SECONDS="${CLASSIFICATION_PERSISTENCE_API_STARTUP_SECONDS:-45}"
CLASSIFICATION_PERSISTENCE_REPORT_DIR="${CLASSIFICATION_PERSISTENCE_REPORT_DIR:-./artifacts/classification-persistence}"
classifier_api_pid=""
classifier_api_started="false"
classifier_api_log=""
mkdir -p "$CLASSIFICATION_PERSISTENCE_REPORT_DIR"

cleanup_classifier_api() {
  if [[ "$classifier_api_started" != "true" ]]; then
    return 0
  fi
  if [[ -n "$classifier_api_pid" ]] && kill -0 "$classifier_api_pid" 2>/dev/null; then
    kill "$classifier_api_pid" >/dev/null 2>&1 || true
    wait "$classifier_api_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup_classifier_api EXIT

classifier_api_port_open() {
  local host="$1"
  local port="$2"
  python3 - <<'PY' "$host" "$port"
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
try:
    with socket.create_connection((host, port), timeout=1):
        pass
except OSError:
    raise SystemExit(1)
PY
}

wait_for_classifier_api() {
  local url="$1"
  local timeout_seconds="$2"
  local curl_insecure_flag=""
  if [[ "$API_SCHEME" == "https" ]]; then
    curl_insecure_flag="-k"
  fi
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if curl ${curl_insecure_flag:+"$curl_insecure_flag"} -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      echo "❌ FAIL: timed out waiting for classification API at ${url}" >&2
      return 1
    fi
    sleep 1
  done
}

ensure_classifier_api() {
  local health_url="${API_URL%/}/health"
  local curl_insecure_flag=""
  if [[ "$API_SCHEME" == "https" ]]; then
    curl_insecure_flag="-k"
  fi
  if curl ${curl_insecure_flag:+"$curl_insecure_flag"} -fsS "$health_url" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$CLASSIFICATION_PERSISTENCE_START_API" != "true" ]]; then
    echo "❌ FAIL: classification API not reachable at ${API_URL}" >&2
    exit 1
  fi
  if [[ ! -x "$CLASSIFICATION_PERSISTENCE_API_PYTHON" ]]; then
    CLASSIFICATION_PERSISTENCE_API_PYTHON="python3"
  fi
  local api_host api_port
  api_host="$(python3 - <<'PY' "$API_URL"
import sys
from urllib.parse import urlparse
parsed = urlparse(sys.argv[1])
print(parsed.hostname or "127.0.0.1")
PY
)"
  api_port="$(python3 - <<'PY' "$API_URL"
import sys
from urllib.parse import urlparse
parsed = urlparse(sys.argv[1])
print(parsed.port or 8787)
PY
)"
  if classifier_api_port_open "$api_host" "$api_port"; then
    local alternate_port
    alternate_port="$(python3 - <<'PY' "$api_host" "$api_port"
import socket
import sys

host = sys.argv[1]
start_port = int(sys.argv[2])
# Skip the immediate adjacent range to avoid colliding with DAST's dedicated default port.
for candidate in range(start_port + 10, start_port + 110):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((host, candidate))
        except OSError:
            continue
        print(candidate)
        break
PY
)"
    if [[ -n "$alternate_port" ]]; then
      api_port="$alternate_port"
      API_URL="${API_SCHEME}://${api_host}:${api_port}"
      health_url="${API_URL%/}/health"
      echo "ℹ️  Classification API port ${api_host}:${api_port} selected because the default port is in use."
    fi
  fi
  echo "▶ Starting classification API for persistence verification at ${API_URL}"
  classifier_api_log="${CLASSIFICATION_PERSISTENCE_REPORT_DIR}/classification-api-startup.log"
  local insecure_http_flag="false"
  if [[ "$API_SCHEME" == "http" ]]; then
    insecure_http_flag="true"
  fi
  echo "  classifier startup log: ${classifier_api_log}"
  TELLER_CLASSIFIER_API_HOST="$api_host" TELLER_CLASSIFIER_API_PORT="$api_port" \
    TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP="$insecure_http_flag" \
    "$CLASSIFICATION_PERSISTENCE_API_PYTHON" "./21_run_classification_api.py" >"$classifier_api_log" 2>&1 &
  classifier_api_pid="$!"
  classifier_api_started="true"
  if ! wait_for_classifier_api "$health_url" "$CLASSIFICATION_PERSISTENCE_API_STARTUP_SECONDS"; then
    echo "❌ FAIL: classification API failed to become ready at ${API_URL}" >&2
    if [[ -n "$classifier_api_log" ]]; then
      echo "Classifier startup log: ${classifier_api_log}" >&2
    fi
    exit 1
  fi
}

ensure_classifier_api

#R005: Auto-resolve transaction/category identifiers when env vars are omitted.
db_scalar() {
  PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${PG_SSLMODE:-disable}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "$1"
}
if [[ "$STRICT_IDS" == true ]]; then
  : "${TXN_ID:?Set TXN_ID to a valid teller.transaction.transaction_id}"
  : "${CATEGORY_ID:?Set CATEGORY_ID to a valid teller.nys_snw_category.nys_snw_category_id}"
else
  if [[ -z "${TXN_ID:-}" ]]; then
    TXN_ID="$(db_scalar "SELECT transaction_id FROM teller.transaction WHERE status = 'posted' ORDER BY date DESC, transaction_id DESC LIMIT 1;")"
  fi
  if [[ -z "${CATEGORY_ID:-}" ]]; then
    CATEGORY_ID="$(db_scalar "SELECT nys_snw_category_id FROM teller.nys_snw_category ORDER BY nys_snw_category_id LIMIT 1;")"
  fi
  if [[ -z "${TXN_ID:-}" ]]; then
    echo "Unable to auto-resolve TXN_ID: no posted rows found in teller.transaction." >&2
    echo "Load/import transactions first, or run with TXN_ID=... (or --require-env-ids)." >&2
    exit 1
  fi
  if [[ -z "${CATEGORY_ID:-}" ]]; then
    echo "Unable to auto-resolve CATEGORY_ID: no rows found in teller.nys_snw_category." >&2
    echo "Seed categories first, or run with CATEGORY_ID=... (or --require-env-ids)." >&2
    exit 1
  fi
fi

#R020: Submit classification update payload to classifier API.
API_RESPONSE="<request failed>"
request_curl_insecure_flag=""
if [[ "$API_SCHEME" == "https" ]]; then
  request_curl_insecure_flag="-k"
fi
if ! API_RESPONSE="$(curl ${request_curl_insecure_flag:+"$request_curl_insecure_flag"} -f -sS -X POST "${API_URL}/v1/transactions/classifications" \
  -H "Content-Type: application/json" \
  -H "X-Teller-Write-Token: ${WRITE_TOKEN}" \
  -d "{\"updates\":[{\"transaction_id\":\"${TXN_ID}\",\"nys_snw_category_id\":${CATEGORY_ID}}]}")"; then
  echo "API response: ${API_RESPONSE}"
  echo "Persisted row: <not checked>"
  if [[ -n "$classifier_api_log" ]]; then
    echo "Classifier startup log: ${classifier_api_log}" >&2
  fi
  echo "❌ FAIL: classification API request failed for transaction_id=${TXN_ID} nys_snw_category_id=${CATEGORY_ID}" >&2
  exit 1
fi

#R025: Query latest persisted classification row for target transaction.
PERSISTED_LINE="$(PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${PG_SSLMODE:-disable}" psql \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT transaction_id || ':' || nys_snw_category_id || ':' || type
   FROM teller.transaction_nys_snw_category
   WHERE transaction_id='${TXN_ID}'
   ORDER BY updated_at DESC
   LIMIT 1;")"
EXPECTED_LINE="${TXN_ID}:${CATEGORY_ID}:user"
echo "API response: ${API_RESPONSE}"
echo "Persisted row: ${PERSISTED_LINE:-<empty>}"
#R030: Print explicit pass/fail status after reporting API and persisted-row details.
if [[ "$PERSISTED_LINE" == "$EXPECTED_LINE" ]]; then
  echo "✅ PASS: persisted classification ${PERSISTED_LINE}"
else
  echo "❌ FAIL: expected ${EXPECTED_LINE} but got ${PERSISTED_LINE:-<empty>}" >&2
  exit 1
fi
