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
  if ! command -v 1psa >/dev/null 2>&1; then
    echo "❌ FAIL: TELLER_DB_PASSWORD is unset and 1psa is unavailable for fallback lookup."
    exit 1
  fi
  DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-localhost_postgres_teller}")"
fi

#R015: Refuse verification when DB password resolves empty.
if [[ -z "$DB_PASSWORD" ]]; then
  echo "❌ FAIL: Failed to resolve teller DB password."
  exit 1
fi

db_scalar() {
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 \
    -Atc "$1"
}

db_lines() {
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 \
    -At \
    -c "$1"
}

failures=()
record_failure() {
  failures+=("$1")
}

#R020: Verify required deployed roles exist.
missing_roles="$(
  db_lines "
    WITH expected(role_name) AS (
      VALUES
        ('teller_read'),
        ('teller_write'),
        ('teller_admin'),
        ('teller')
    )
    SELECT expected.role_name
    FROM expected
    LEFT JOIN pg_roles
      ON pg_roles.rolname = expected.role_name
    WHERE pg_roles.rolname IS NULL
    ORDER BY expected.role_name;
  "
)"
if [[ -n "$missing_roles" ]]; then
  record_failure "missing roles: ${missing_roles//$'\n'/, }"
fi

#R020: Verify required deployed schema exists.
if [[ "$(db_scalar "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'teller');")" != "t" ]]; then
  record_failure "missing schema: teller"
fi

#R020: Verify core relations from deploy are present.
missing_tables="$(
  db_lines "
    WITH expected(table_name) AS (
      VALUES
        ('institution'),
        ('account_links'),
        ('account'),
        ('identity'),
        ('identity_name'),
        ('identity_email'),
        ('identity_phone_number'),
        ('identity_address_data'),
        ('identity_address'),
        ('account_identities'),
        ('routing_numbers'),
        ('account_details_links'),
        ('account_details'),
        ('account_balances_links'),
        ('account_balances'),
        ('transaction_type'),
        ('transaction_details_counterparty'),
        ('transaction_links'),
        ('transaction_details'),
        ('transaction'),
        ('nys_snw_category'),
        ('transaction_nys_snw_category')
    )
    SELECT expected.table_name
    FROM expected
    LEFT JOIN information_schema.tables tables
      ON tables.table_schema = 'teller'
     AND tables.table_name = expected.table_name
     AND tables.table_type = 'BASE TABLE'
    WHERE tables.table_name IS NULL
    ORDER BY expected.table_name;
  "
)"
if [[ -n "$missing_tables" ]]; then
  record_failure "missing teller tables: ${missing_tables//$'\n'/, }"
fi

#R020: Verify the deployed transaction info view exists and remains queryable.
if [[ "$(db_scalar "SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'teller' AND table_name = 'transaction_info_view');")" != "t" ]]; then
  record_failure "missing view: teller.transaction_info_view"
elif ! db_scalar "SELECT 1 FROM teller.transaction_info_view LIMIT 1;" >/dev/null; then
  record_failure "view query failed: teller.transaction_info_view"
fi

#R025: Verify classification FK uses ON DELETE CASCADE.
if [[ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class child_rel
      ON child_rel.oid = con.conrelid
    JOIN pg_namespace child_ns
      ON child_ns.oid = child_rel.relnamespace
    JOIN pg_class parent_rel
      ON parent_rel.oid = con.confrelid
    JOIN pg_namespace parent_ns
      ON parent_ns.oid = parent_rel.relnamespace
    WHERE con.contype = 'f'
      AND child_ns.nspname = 'teller'
      AND child_rel.relname = 'transaction_nys_snw_category'
      AND parent_ns.nspname = 'teller'
      AND parent_rel.relname = 'transaction'
      AND con.confdeltype = 'c'
  );
")" != "t" ]]; then
  record_failure "classification FK is missing ON DELETE CASCADE"
fi

#R030: Verify updated_at trigger function and table trigger exist.
if [[ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
    FROM pg_proc proc
    JOIN pg_namespace ns
      ON ns.oid = proc.pronamespace
    WHERE ns.nspname = 'teller'
      AND proc.proname = 'update_updated_at'
  );
")" != "t" ]]; then
  record_failure "missing function: teller.update_updated_at()"
fi

if [[ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
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
      AND rel.relname = 'transaction_nys_snw_category'
      AND proc_ns.nspname = 'teller'
      AND proc.proname = 'update_updated_at'
      AND trg.tgisinternal = false
      AND trg.tgenabled <> 'D'
  );
")" != "t" ]]; then
  record_failure "missing updated_at trigger on teller.transaction_nys_snw_category"
fi

#R035: Print explicit pass/fail verification result.
if (( ${#failures[@]} > 0 )); then
  echo "❌ FAIL: Database deployment verification failed."
  for failure in "${failures[@]}"; do
    echo "- ${failure}"
  done
  exit 1
fi

echo "✅ PASS: Database deployment verified (roles, schema, core relations, FK cascade, trigger wiring)."
