#!/usr/bin/env zsh
set -euo pipefail

: "${TXN_ID:?Set TXN_ID to a valid teller.transaction.transaction_id}"
: "${CATEGORY_ID:?Set CATEGORY_ID to a valid teller.nys_snw_category.nys_snw_category_id}"
API_URL="${TELLER_CLASSIFIER_API_URL:-http://127.0.0.1:8787}"
DB_HOST="${TELLER_DB_HOST:-localhost}"
DB_PORT="${TELLER_DB_PORT:-5432}"
DB_NAME="${TELLER_DB_NAME:-prod}"
DB_USER="${TELLER_DB_USER:-teller}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-}"

if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-localhost_postgres_teller}")"
fi

curl -sS -X POST "${API_URL}/v1/transactions/classifications" \
  -H "Content-Type: application/json" \
  -d "{\"updates\":[{\"transaction_id\":\"${TXN_ID}\",\"nys_snw_category_id\":${CATEGORY_ID}}]}"

PGPASSWORD="$DB_PASSWORD" psql \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc \
  "SELECT transaction_id || ':' || nys_snw_category_id || ':' || type
   FROM teller.transaction_nys_snw_category
   WHERE transaction_id='${TXN_ID}'
   ORDER BY updated_at DESC
   LIMIT 1;"
