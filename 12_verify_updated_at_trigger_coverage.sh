#!/usr/bin/env zsh
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Support configurable database connection defaults.
DB_HOST="${TELLER_DB_HOST:-localhost}"
DB_PORT="${TELLER_DB_PORT:-5432}"
DB_NAME="${TELLER_DB_NAME:-prod}"
DB_USER="${TELLER_DB_USER:-teller}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-}"

#R010: Resolve DB password from environment or 1psa fallback.
if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-localhost_postgres_teller}")"
fi

#R015: Refuse verification when DB password resolves empty.
if [[ -z "$DB_PASSWORD" ]]; then
  echo "Failed to resolve teller DB password."
  exit 1
fi

MISSING_TABLES_SQL="
WITH expected AS (
  SELECT tables.table_name
  FROM information_schema.tables tables
  JOIN information_schema.columns columns
    ON columns.table_schema = tables.table_schema
   AND columns.table_name = tables.table_name
  WHERE tables.table_schema = 'teller'
    AND tables.table_type = 'BASE TABLE'
    AND columns.column_name = 'updated_at'
),
actual AS (
  SELECT DISTINCT rel.relname AS table_name
  FROM pg_trigger trg
  JOIN pg_class rel
    ON rel.oid = trg.tgrelid
  JOIN pg_namespace rel_ns
    ON rel_ns.oid = rel.relnamespace
  JOIN pg_proc proc
    ON proc.oid = trg.tgfoid
  JOIN pg_namespace proc_ns
    ON proc_ns.oid = proc.pronamespace
  WHERE rel_ns.nspname = 'teller'
    AND proc_ns.nspname = 'teller'
    AND proc.proname = 'update_updated_at'
    AND trg.tgisinternal = false
    AND trg.tgenabled <> 'D'
)
SELECT expected.table_name
FROM expected
LEFT JOIN actual
  ON actual.table_name = expected.table_name
WHERE actual.table_name IS NULL
ORDER BY expected.table_name;
"

#R020: Query and report tables missing updated_at trigger coverage.
missing_tables="$(
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -At \
    -c "$MISSING_TABLES_SQL"
)"

#R025: Exit non-zero when any table is missing trigger coverage.
if [[ -n "$missing_tables" ]]; then
  echo "Missing teller.update_updated_at trigger coverage:"
  while IFS= read -r table_name; do
    [[ -n "$table_name" ]] || continue
    echo "- $table_name"
  done <<< "$missing_tables"
  exit 1
fi

#R030: Print success message when all updated_at tables are covered.
echo "All teller tables with updated_at are covered by teller.update_updated_at."
