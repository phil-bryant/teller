#!/usr/bin/env zsh
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

#R010: Support configurable API/DB endpoints with defaults.
API_URL="${TELLER_CLASSIFIER_API_URL:-http://127.0.0.1:8787}"
DB_HOST="${TELLER_DB_HOST:-localhost}"
DB_PORT="${TELLER_DB_PORT:-5432}"
DB_NAME="${TELLER_DB_NAME:-prod}"
DB_USER="${TELLER_DB_USER:-teller}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-}"

#R015: Resolve DB password from env or 1psa fallback.
if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-localhost_postgres_teller}")"
fi

#R005: Auto-resolve transaction/category identifiers when env vars are omitted.
db_scalar() {
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "$1"
}
if [[ "$STRICT_IDS" == true ]]; then
  : "${TXN_ID:?Set TXN_ID to a valid teller.transaction.transaction_id}"
  : "${CATEGORY_ID:?Set CATEGORY_ID to a valid teller.nys_snw_category.nys_snw_category_id}"
else
  if [[ -z "${TXN_ID:-}" ]]; then
    TXN_ID="$(db_scalar "SELECT transaction_id FROM teller.transaction ORDER BY date DESC, transaction_id DESC LIMIT 1;")"
  fi
  if [[ -z "${CATEGORY_ID:-}" ]]; then
    CATEGORY_ID="$(db_scalar "SELECT nys_snw_category_id FROM teller.nys_snw_category ORDER BY nys_snw_category_id LIMIT 1;")"
  fi
  if [[ -z "${TXN_ID:-}" ]]; then
    echo "Unable to auto-resolve TXN_ID: no rows found in teller.transaction." >&2
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
if ! API_RESPONSE="$(curl -f -sS -X POST "${API_URL}/v1/transactions/classifications" \
  -H "Content-Type: application/json" \
  -d "{\"updates\":[{\"transaction_id\":\"${TXN_ID}\",\"nys_snw_category_id\":${CATEGORY_ID}}]}")"; then
  echo "API response: ${API_RESPONSE}"
  echo "Persisted row: <not checked>"
  echo "❌ FAIL: classification API request failed for transaction_id=${TXN_ID} nys_snw_category_id=${CATEGORY_ID}" >&2
  exit 1
fi

#R025: Query latest persisted classification row for target transaction.
PERSISTED_LINE="$(PGPASSWORD="$DB_PASSWORD" psql \
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
