#!/usr/bin/env zsh
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Require transaction and category identifiers from environment.
: "${TXN_ID:?Set TXN_ID to a valid teller.transaction.transaction_id}"
: "${CATEGORY_ID:?Set CATEGORY_ID to a valid teller.nys_snw_category.nys_snw_category_id}"
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

#R020: Submit classification update payload to classifier API.
curl -sS -X POST "${API_URL}/v1/transactions/classifications" \
  -H "Content-Type: application/json" \
  -d "{\"updates\":[{\"transaction_id\":\"${TXN_ID}\",\"nys_snw_category_id\":${CATEGORY_ID}}]}"

#R025: Query latest persisted classification row for target transaction.
PGPASSWORD="$DB_PASSWORD" psql \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT transaction_id || ':' || nys_snw_category_id || ':' || type
   FROM teller.transaction_nys_snw_category
   WHERE transaction_id='${TXN_ID}'
   ORDER BY updated_at DESC
   LIMIT 1;"
