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
DB_PROFILE_HELPER="${REPO_ROOT}/src/scripts/db_profile_export.sh"

#R050: Resolve target/profile so verification can adapt to local vs managed Postgres.
PROFILE_NAME="local"
PROFILE_TARGET="local"
PG_ONEPSA_ITEM=""
PG_SSLMODE="disable"
if [[ ! -x "$DB_PROFILE_HELPER" ]]; then
  echo "❌ FAIL: DB profile helper is missing or not executable: ${DB_PROFILE_HELPER}"
  exit 1
fi
#R050: Load and validate profile export lines before verification.
load_profile_exports_from_file() {
  local exports_file="$1"
  local invalid_lines=""
  invalid_lines="$(awk '
    !/^(export )?[A-Za-z_][A-Za-z0-9_]*=.*/ { print; next }
    {
      key=$0
      sub(/^export[[:space:]]+/, "", key)
      sub(/=.*/, "", key)
      if (key !~ /^(DB_DIALECT|PROFILE_NAME|PROFILE_TARGET|PG_HOST|PG_PORT|PG_DBNAME|PG_USER|PG_SSLMODE|PG_SEARCH_PATH|PG_RUNTIME_ROLE|PG_ONEPSA_ITEM|SQLITE_PATH)$/) {
        print
      }
    }
  ' "$exports_file")"
  if [[ -n "$invalid_lines" ]]; then
    echo "❌ FAIL: refusing to load unexpected profile export lines:"
    printf '%s\n' "$invalid_lines"
    return 1
  fi
  unset DB_DIALECT PROFILE_NAME PROFILE_TARGET PG_HOST PG_PORT PG_DBNAME PG_USER
  unset PG_SSLMODE PG_SEARCH_PATH PG_RUNTIME_ROLE PG_ONEPSA_ITEM SQLITE_PATH SQLCIPHER_KEY
  set -a
  # shellcheck disable=SC1090
  source "$exports_file"
  set +a
}

#R055: Resolve SQLCipher key from profile helper output.
resolve_sqlcipher_key_from_profile() {
  "$DB_PROFILE_HELPER" --print-sqlcipher-key
}

profile_exports_file="$(mktemp)"
if ! "$DB_PROFILE_HELPER" >"$profile_exports_file"; then
  #R065: Refuse verification when DB profile setup is missing.
  rm -f "$profile_exports_file"
  exit 1
fi
if ! load_profile_exports_from_file "$profile_exports_file"; then
  rm -f "$profile_exports_file"
  exit 1
fi
rm -f "$profile_exports_file"
DB_DIALECT="${DB_DIALECT:-postgresql}"

#R066: Run SQLite-specific verification checks when the active profile target is SQLite.
if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
  SQLITE_DB_PATH="${SQLITE_PATH:-${TELLER_DB_SQLITE_PATH:-}}"
  SQLITE_CIPHER_KEY="${TELLER_DB_SQLCIPHER_KEY:-}"
  if [[ -z "$SQLITE_CIPHER_KEY" ]]; then
    if ! SQLITE_CIPHER_KEY="$(resolve_sqlcipher_key_from_profile)"; then
      echo "❌ FAIL: SQLite verification could not resolve SQLCipher key from profile helper."
      exit 1
    fi
  fi
  SQLITE_ESCAPED_KEY="$(printf "%s" "$SQLITE_CIPHER_KEY" | sed "s/'/''/g")"
  #R066: Run scalar sqlite verification query via sqlcipher client.
  sqlcipher_scalar() {
    local query="$1"
    sqlcipher "$SQLITE_DB_PATH" <<SQL
.bail on
PRAGMA key='${SQLITE_ESCAPED_KEY}';
${query}
SQL
  }
  if [[ -z "$SQLITE_DB_PATH" ]]; then
    echo "❌ FAIL: SQLite verification requires SQLITE_PATH from db profile export."
    exit 1
  fi
  if [[ -z "$SQLITE_CIPHER_KEY" ]]; then
    echo "❌ FAIL: SQLite verification requires SQLCIPHER_KEY via TELLER_DB_SQLCIPHER_KEY or profile sqlcipher_key."
    exit 1
  fi
  if [[ ! -f "$SQLITE_DB_PATH" ]]; then
    echo "❌ FAIL: SQLite database file is missing: ${SQLITE_DB_PATH}"
    exit 1
  fi
  if ! command -v sqlcipher >/dev/null 2>&1; then
    echo "❌ FAIL: sqlcipher is required for sqlite verification."
    exit 1
  fi
  required_tables=(
    institution
    account
    transaction_type
    "transaction"
    nys_snw_category
    transaction_nys_snw_category
    transaction_email_match
  )
  failures=()
  for table_name in "${required_tables[@]}"; do
    exists="$(sqlcipher_scalar "SELECT 1 FROM sqlite_master WHERE type='table' AND name='${table_name}' LIMIT 1;" | tr -d '\r\n')"
    if [[ "$exists" != "1" ]]; then
      failures+=("missing sqlite table: ${table_name}")
    fi
  done
  view_exists="$(sqlcipher_scalar "SELECT 1 FROM sqlite_master WHERE type='view' AND name='transaction_info_view' LIMIT 1;" | tr -d '\r\n')"
  if [[ "$view_exists" != "1" ]]; then
    failures+=("missing sqlite view: transaction_info_view")
  fi
  if (( ${#failures[@]} > 0 )); then
    echo "❌ FAIL: Database deployment verification failed."
    for failure in "${failures[@]}"; do
      echo "- ${failure}"
    done
    exit 1
  fi
  sqlcipher_scalar "SELECT 1 FROM transaction_info_view LIMIT 1;" >/dev/null 2>&1 || {
    echo "❌ FAIL: sqlite transaction_info_view is not queryable."
    exit 1
  }
  echo "✅ PASS: Database deployment verified (sqlite tables/view/invariants)."
  exit 0
fi

#R005: Use connection settings exclusively from the resolved profile (1psa or ~/.env via the helper).
#R005: Env vars TELLER_DB_* still override for CI/test fixtures.
DB_HOST="${TELLER_DB_HOST:-${PG_HOST:-}}"
DB_PORT="${TELLER_DB_PORT:-${PG_PORT:-}}"
DB_NAME="${TELLER_DB_NAME:-${PG_DBNAME:-}}"
DB_USER="${TELLER_DB_USER:-${PG_USER:-}}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-}"

if [[ -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" ]]; then
  echo "❌ FAIL: Resolved profile is missing host/port/dbname/user; check the 1psa item or ~/.env."
  exit 1
fi

#R005: Print the resolved deploy target so the operator sees where verification is running.
echo "ℹ️  Verifying database via profile=${PROFILE_NAME} target=${PROFILE_TARGET} host=${DB_HOST} port=${DB_PORT} db=${DB_NAME} user=${DB_USER}"

#R055: Resolve DB password from environment or profile-driven 1psa fallback.
#R010: Resolve DB password from environment or 1psa fallback.
if [[ -z "$DB_PASSWORD" ]]; then
  PSA_ITEM="${TELLER_PSA_ITEM:-${PG_ONEPSA_ITEM:-}}"
  if [[ -z "$PSA_ITEM" ]]; then
    echo "❌ FAIL: No 1psa item resolved from config/db-profiles.json; cannot look up password."
    exit 1
  fi
  if ! DB_PASSWORD="$(rb_read_1psa_item "$PSA_ITEM" "password")"; then
    echo "❌ FAIL: Failed to resolve teller DB password from item '${PSA_ITEM}'."
    exit 1
  fi
fi

#R015: Refuse verification when DB password resolves empty.
if [[ -z "$DB_PASSWORD" ]]; then
  echo "❌ FAIL: Failed to resolve teller DB password."
  exit 1
fi

#R020: Run scalar postgres verification query for schema checks.
db_scalar() {
  PGPASSWORD="$DB_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 \
    -Atc "$1"
}

#R040: Run postgres verification query returning newline-delimited rows.
db_lines() {
  PGPASSWORD="$DB_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 \
    -At \
    -c "$1"
}

failures=()
#R035: Record explicit verification failure for final report output.
record_failure() {
  failures+=("$1")
}

#R050: Skip teller_*-role existence check on managed targets where those roles do not exist.
if [[ "$PROFILE_TARGET" != "managed" ]]; then
  #R020: Verify required deployed roles exist.
  missing_roles="$(
    db_lines "
      WITH expected(role_name) AS (
        VALUES
          ('teller_read'),
          ('teller_write'),
          ('teller_admin'),
          ('teller_ingest_writer'),
          ('teller_api_reader'),
          ('teller_api_writer'),
          ('teller_migration_admin'),
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

#R040: Verify every teller table with updated_at is covered by teller.update_updated_at.
missing_updated_at_coverage="$(
  db_lines "
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
)"
if [[ -n "$missing_updated_at_coverage" ]]; then
  #R045: Surface all missing table names as explicit verification failures.
  while IFS= read -r table_name; do
    [[ -n "$table_name" ]] || continue
    record_failure "missing updated_at trigger coverage: ${table_name}"
  done <<< "$missing_updated_at_coverage"
fi

if [[ "$PROFILE_TARGET" != "managed" ]]; then
  # Verify single-tenant RLS is enabled on high-risk financial/PII tables.
  rls_gaps="$(
  db_lines "
    WITH expected(table_name) AS (
      VALUES
        ('transaction'),
        ('account_details'),
        ('identity_email'),
        ('identity_phone_number'),
        ('identity_address_data'),
        ('transaction_nys_snw_category'),
        ('transaction_email_candidate'),
        ('transaction_email_match')
    )
    SELECT expected.table_name
    FROM expected
    LEFT JOIN pg_class rel
      ON rel.relname = expected.table_name
    LEFT JOIN pg_namespace rel_ns
      ON rel_ns.oid = rel.relnamespace
    WHERE rel_ns.nspname = 'teller'
      AND (
        rel.relrowsecurity IS DISTINCT FROM TRUE
        OR rel.relforcerowsecurity IS DISTINCT FROM TRUE
      )
    ORDER BY expected.table_name;
  "
  )"
  if [[ -n "$rls_gaps" ]]; then
    while IFS= read -r table_name; do
      [[ -n "$table_name" ]] || continue
      record_failure "missing enforced RLS on teller.${table_name}"
    done <<< "$rls_gaps"
  fi

# Verify secure views for PII-facing read paths are present.
  missing_secure_views="$(
  db_lines "
    WITH expected(view_name) AS (
      VALUES
        ('account_details_secure_v1'),
        ('identity_email_secure_v1'),
        ('identity_phone_number_secure_v1'),
        ('identity_address_data_secure_v1'),
        ('audit_log_export_v1')
    )
    SELECT expected.view_name
    FROM expected
    LEFT JOIN information_schema.views views
      ON views.table_schema = 'teller'
     AND views.table_name = expected.view_name
    WHERE views.table_name IS NULL
    ORDER BY expected.view_name;
  "
  )"
  if [[ -n "$missing_secure_views" ]]; then
    record_failure "missing security views: ${missing_secure_views//$'\n'/, }"
  fi

# Verify hash/masked columns exist for restricted PII fields.
  missing_pii_columns="$(
  db_lines "
    WITH expected(table_name, column_name) AS (
      VALUES
        ('account_details', 'account_number_hash'),
        ('account_details', 'account_number_masked'),
        ('identity_email', 'data_hash'),
        ('identity_email', 'data_masked'),
        ('identity_phone_number', 'data_hash'),
        ('identity_phone_number', 'data_masked'),
        ('identity_address_data', 'address_hash'),
        ('identity_address_data', 'address_masked')
    )
    SELECT expected.table_name || '.' || expected.column_name
    FROM expected
    LEFT JOIN information_schema.columns columns
      ON columns.table_schema = 'teller'
     AND columns.table_name = expected.table_name
     AND columns.column_name = expected.column_name
    WHERE columns.column_name IS NULL
    ORDER BY expected.table_name, expected.column_name;
  "
  )"
  if [[ -n "$missing_pii_columns" ]]; then
    record_failure "missing PII protection columns: ${missing_pii_columns//$'\n'/, }"
  fi

# Verify enriched audit evidence columns and support objects.
  missing_audit_columns="$(
  db_lines "
    WITH expected(column_name) AS (
      VALUES
        ('request_id'),
        ('actor_id'),
        ('actor_service'),
        ('session_role'),
        ('app_context')
    )
    SELECT expected.column_name
    FROM expected
    LEFT JOIN information_schema.columns columns
      ON columns.table_schema = 'teller'
     AND columns.table_name = 'audit_log'
     AND columns.column_name = expected.column_name
    WHERE columns.column_name IS NULL
    ORDER BY expected.column_name;
  "
  )"
  if [[ -n "$missing_audit_columns" ]]; then
    record_failure "missing audit evidence columns: ${missing_audit_columns//$'\n'/, }"
  fi

  if [[ "$(db_scalar "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'teller' AND table_name = 'security_event_log');")" != "t" ]]; then
    record_failure "missing table: teller.security_event_log"
  fi

  if [[ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
    FROM pg_proc proc
    JOIN pg_namespace ns
      ON ns.oid = proc.pronamespace
    WHERE ns.nspname = 'teller'
      AND proc.proname = 'log_security_event'
  );
  ")" != "t" ]]; then
    record_failure "missing function: teller.log_security_event(...)"
  fi

  if [[ "$(db_scalar "
  SELECT EXISTS (
    SELECT 1
    FROM pg_proc proc
    JOIN pg_namespace ns
      ON ns.oid = proc.pronamespace
    WHERE ns.nspname = 'teller'
      AND proc.proname = 'purge_audit_log_before'
  );
  ")" != "t" ]]; then
    record_failure "missing function: teller.purge_audit_log_before(...)"
  fi
fi

#R060: When the resolved profile requires TLS, confirm the live connection is encrypted.
if [[ "${PG_SSLMODE:-}" == "require" || "${PG_SSLMODE:-}" == "verify-ca" || "${PG_SSLMODE:-}" == "verify-full" ]]; then
  ssl_active="$(db_scalar "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();")"
  if [[ "$ssl_active" != "t" ]]; then
    record_failure "sslmode=${PG_SSLMODE} but pg_stat_ssl reports the connection is not encrypted (got '${ssl_active}')"
  fi
fi

#R035: Print explicit pass/fail verification result.
if (( ${#failures[@]} > 0 )); then
  echo "❌ FAIL: Database deployment verification failed."
  for failure in "${failures[@]}"; do
    echo "- ${failure}"
  done
  exit 1
fi

echo "✅ PASS: Database deployment verified (roles, schema, core relations, FK cascade, trigger coverage, and security hardening controls)."
