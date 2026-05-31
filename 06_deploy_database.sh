#!/usr/bin/env bash
#R001: Fail fast on unrecoverable SQL/bootstrap errors.
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
#R035: Resolve SQL directory relative to script location.
SQL_DIR="${SCRIPT_DIR}/src/sql/postgres"
SQLITE_SQL_DIR="${SCRIPT_DIR}/src/sql/sqlite"
#R060: Resolve the active DB profile so we know whether to deploy locally or to a managed target.
DB_PROFILE_HELPER="${SCRIPT_DIR}/src/scripts/db_profile_export.sh"

#R060: Read the resolved profile via the shared helper. For managed targets we force the
#R060: "supabase_direct" profile so DDL never goes through the transaction pooler.
#R090: Refuse deploy when profile resolution fails (no implicit local fallback).
if [[ ! -x "$DB_PROFILE_HELPER" ]]; then
    echo "DB profile helper is missing or not executable: ${DB_PROFILE_HELPER}"
    exit 1
fi
load_profile_exports_from_file() {
    local exports_file="$1"
    local invalid_lines=""
    invalid_lines="$(awk '
        !/^(export )?[A-Za-z_][A-Za-z0-9_]*=.*/ { print; next }
        {
            key=$0
            sub(/^export[[:space:]]+/, "", key)
            sub(/=.*/, "", key)
            if (key !~ /^(DB_DIALECT|PROFILE_NAME|PROFILE_TARGET|PG_HOST|PG_PORT|PG_DBNAME|PG_USER|PG_SSLMODE|PG_SEARCH_PATH|PG_RUNTIME_ROLE|PG_ONEPSA_ITEM|SQLITE_PATH|SQLCIPHER_KEY)$/) {
                print
            }
        }
    ' "$exports_file")"
    if [[ -n "$invalid_lines" ]]; then
        echo "Refusing to load unexpected profile export lines:"
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

require_nonempty_env() {
    local scope="$1"
    shift
    local var_name
    for var_name in "$@"; do
        if [[ -z "${!var_name:-}" ]]; then
            echo "${scope} requires non-empty ${var_name}; check config/db-profiles.json or the profile 1psa item."
            exit 1
        fi
    done
}

is_valid_pg_identifier() {
    local identifier="$1"
    [[ "$identifier" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]
}

profile_exports_file="$(mktemp)"
if ! "$DB_PROFILE_HELPER" >"$profile_exports_file"; then
    rm -f "$profile_exports_file"
    exit 1
fi
if ! load_profile_exports_from_file "$profile_exports_file"; then
    rm -f "$profile_exports_file"
    exit 1
fi
rm -f "$profile_exports_file"
require_nonempty_env "Profile resolution" PROFILE_NAME PROFILE_TARGET
DB_DIALECT="${DB_DIALECT:-postgresql}"
if [[ "$DB_DIALECT" != "sqlite" && "${PROFILE_TARGET:-local}" != "sqlite" ]]; then
    require_nonempty_env "Profile resolution" PG_DBNAME PG_USER
fi
PG_SSLMODE="${PG_SSLMODE:-}"

#R060: Print the resolved deploy target so the operator sees where deploy is running.
echo "ℹ️  Deploying database via profile=${PROFILE_NAME} target=${PROFILE_TARGET} dialect=${DB_DIALECT}${PG_HOST:+ host=${PG_HOST}}${PG_PORT:+ port=${PG_PORT}}${PG_DBNAME:+ db=${PG_DBNAME}}${PG_USER:+ user=${PG_USER}}"

#R006: Ensure psql stops immediately on SQL errors.
PSQL_OPTS=(-v ON_ERROR_STOP=1)

#R071: Apply SQLite schema files through the existing deploy entrypoint.
if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
    SQLITE_DB_PATH="${SQLITE_PATH:-}"
    SQLITE_CIPHER_KEY="${SQLCIPHER_KEY:-${TELLER_DB_SQLCIPHER_KEY:-}}"
    SQLITE_SCHEMA_FILE="${SQLITE_SQL_DIR}/create_database.sql"
    if [[ -z "$SQLITE_DB_PATH" ]]; then
        echo "SQLite deploy requires SQLITE_PATH from db profile export."
        exit 1
    fi
    if [[ -z "$SQLITE_CIPHER_KEY" ]]; then
        echo "SQLite deploy requires SQLCIPHER_KEY (or TELLER_DB_SQLCIPHER_KEY) from db profile export."
        exit 1
    fi
    if ! command -v sqlcipher >/dev/null 2>&1; then
        echo "sqlcipher is required but was not found on PATH."
        exit 1
    fi
    if [[ ! -f "$SQLITE_SCHEMA_FILE" ]]; then
        echo "SQLite schema file is missing: ${SQLITE_SCHEMA_FILE}"
        exit 1
    fi
    mkdir -p "$(dirname "$SQLITE_DB_PATH")"
    echo "ℹ️  Applying sqlite schema file=${SQLITE_SCHEMA_FILE} db=${SQLITE_DB_PATH}"
    SQLITE_ESCAPED_KEY="$(printf "%s" "$SQLITE_CIPHER_KEY" | sed "s/'/''/g")"
    sqlcipher "$SQLITE_DB_PATH" <<SQL
.bail on
PRAGMA key='${SQLITE_ESCAPED_KEY}';
.read "${SQLITE_SCHEMA_FILE}"
SQL
    echo "SQLite deploy complete: ${SQLITE_DB_PATH}"
    exit 0
fi

#R005: Require 1psa before credential lookups.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

if [[ "${PROFILE_TARGET:-local}" == "managed" ]]; then
    #R060: Re-resolve using the direct (non-pooler) profile for DDL apply.
    if [[ "$PROFILE_NAME" != "supabase_direct" && -x "$DB_PROFILE_HELPER" ]]; then
        profile_exports_file="$(mktemp)"
        if ! "$DB_PROFILE_HELPER" --profile supabase_direct >"$profile_exports_file"; then
            rm -f "$profile_exports_file"
            exit 1
        fi
        if ! load_profile_exports_from_file "$profile_exports_file"; then
            rm -f "$profile_exports_file"
            exit 1
        fi
        rm -f "$profile_exports_file"
        require_nonempty_env "Managed direct deploy profile" PROFILE_NAME PG_HOST PG_PORT PG_DBNAME PG_USER
        echo "ℹ️  Switched to direct DDL profile=${PROFILE_NAME} host=${PG_HOST} port=${PG_PORT} db=${PG_DBNAME} user=${PG_USER}"
    fi

    #R065: Resolve managed-target password from the profile's 1psa item; env var still wins.
    MANAGED_PASSWORD="${TELLER_DB_PASSWORD:-}"
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        if [[ -z "${PG_ONEPSA_ITEM:-}" ]]; then
            echo "Managed deploy requires PG_ONEPSA_ITEM (from config/db-profiles.json) or TELLER_DB_PASSWORD."
            exit 1
        fi
        MANAGED_PASSWORD="$(1psa -p "$PG_ONEPSA_ITEM")"
    fi
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        echo "Failed to read managed DB password (item: ${PG_ONEPSA_ITEM})"
        exit 1
    fi

    #R070: Apply schema files using the profile's connection user against the managed target.
    run_psql_managed() {
        PGPASSWORD="$MANAGED_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql "${PSQL_OPTS[@]}" \
            -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DBNAME" "$@"
    }

    #R070: Ensure the teller schema exists before applying schema objects.
    run_psql_managed -c "CREATE SCHEMA IF NOT EXISTS teller;"

    #R070: Apply teller schema files in declared dependency order.
    run_psql_managed -f "${SQL_DIR}/teller_enums.sql"
    run_psql_managed -f "${SQL_DIR}/teller_institution.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account_links.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account.sql"
    run_psql_managed -f "${SQL_DIR}/teller_identity.sql"
    run_psql_managed -f "${SQL_DIR}/teller_identity_name.sql"
    run_psql_managed -f "${SQL_DIR}/teller_identity_email.sql"
    run_psql_managed -f "${SQL_DIR}/teller_identity_phone_number.sql"
    run_psql_managed -f "${SQL_DIR}/teller_identity_address_data.sql"
    run_psql_managed -f "${SQL_DIR}/teller_identity_address.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account_identities.sql"
    run_psql_managed -f "${SQL_DIR}/teller_routing_numbers.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account_details_links.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account_details.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account_balances_links.sql"
    run_psql_managed -f "${SQL_DIR}/teller_account_balances.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_type.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_details_counterparty.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_links.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_details.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction.sql"
    run_psql_managed -f "${SQL_DIR}/teller_nys_snw_category.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_nys_snw_category.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_email_match_run.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_email_candidate.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_email_match.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_email_match_audit.sql"
    #R045: Ensure transaction classification FK cascades deletes from teller.transaction.
    run_psql_managed -c \
"ALTER TABLE teller.transaction_nys_snw_category \
 DROP CONSTRAINT IF EXISTS transaction_nys_snw_category_transaction_id_fkey, \
 ADD CONSTRAINT transaction_nys_snw_category_transaction_id_fkey \
 FOREIGN KEY (transaction_id) REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE;"
    #R040: Attach updated_at triggers only after all updated_at tables exist.
    run_psql_managed -f "${SQL_DIR}/create_triggers.sql"
    run_psql_managed -f "${SQL_DIR}/teller_transaction_info_view.sql"
    run_psql_managed -f "${SQL_DIR}/create_audit.sql"
    #R075: Skip pgtap extension creation on managed targets (extension is not allow-listed).
    #R080: Skip teller_write ingest grants on managed targets (no teller_write role exists there).
    exit 0
fi

#R010: Configurable 1psa source for postgres admin password.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
#R015: Configurable 1psa source for teller user password.
TELLER_PSA_ITEM="${TELLER_PSA_ITEM:-localhost_postgres_teller}"
TELLER_PSA_FIELD="${TELLER_PSA_FIELD:-password}"

#R007: Run SQL as postgres with fail-fast psql options.
run_psql_postgres() {
    PGPASSWORD="$POSTGRES_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql "${PSQL_OPTS[@]}" -U postgres "$@"
}

#R008: Run SQL as teller with fail-fast psql options.
run_psql_teller() {
    PGPASSWORD="$TELLER_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql "${PSQL_OPTS[@]}" \
        -U "$PG_USER" -d "$PG_DBNAME" "$@"
}

#R010: Resolve postgres password from configured item/field.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

#R015: Resolve teller password from configured item/field.
if [ "$TELLER_PSA_FIELD" = "password" ]; then
    TELLER_PASSWORD="$(1psa -p "$TELLER_PSA_ITEM")"
else
    TELLER_PASSWORD="$(1psa -f "$TELLER_PSA_ITEM" "$TELLER_PSA_FIELD")"
fi

#R020: Refuse deployment when postgres password is empty.
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

#R020: Refuse deployment when teller password is empty.
if [ -z "$TELLER_PASSWORD" ]; then
    echo "Failed to read teller password from 1psa item: $TELLER_PSA_ITEM"
    exit 1
fi

#R025: Run admin bootstrap SQL in required order.
#R085: Skip create_database.sql when the resolved DB already exists so re-runs against an existing
#R085: local DB do not error. configure_database.sql is now idempotent on its own.
#R095: Validate profile-resolved DB/user identifiers before SQL execution.
if [[ -z "${PG_DBNAME:-}" || -z "${PG_USER:-}" ]]; then
    echo "Resolved profile is missing PG_DBNAME or PG_USER; check the 1psa item or ~/.env."
    exit 1
fi
if ! is_valid_pg_identifier "$PG_DBNAME"; then
    echo "Resolved PG_DBNAME is not a valid PostgreSQL identifier: ${PG_DBNAME}"
    exit 1
fi
if ! is_valid_pg_identifier "$PG_USER"; then
    echo "Resolved PG_USER is not a valid PostgreSQL identifier: ${PG_USER}"
    exit 1
fi
prod_exists="$(
    #R096: Identifier already validated; use direct SQL for psql -c compatibility.
    PGPASSWORD="$POSTGRES_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql "${PSQL_OPTS[@]}" -U postgres \
        -tAc "SELECT 1 FROM pg_database WHERE datname = '${PG_DBNAME}'"
)"
if [ -z "$prod_exists" ]; then
    run_psql_postgres -v db_name="$PG_DBNAME" -f "${SQL_DIR}/create_database.sql"
fi
run_psql_postgres -d "$PG_DBNAME" -v teller_password="$TELLER_PASSWORD" -v db_name="$PG_DBNAME" -v teller_user="$PG_USER" -f "${SQL_DIR}/configure_database.sql"
#R050: Ensure pgTAP extension exists in the resolved DB for SQL unit test execution.
run_psql_postgres -d "$PG_DBNAME" -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

#R030: Build teller schema objects in declared dependency order.
run_psql_teller -f "${SQL_DIR}/teller_enums.sql"
run_psql_teller -f "${SQL_DIR}/teller_institution.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_account.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_name.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_email.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_phone_number.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_address_data.sql"
run_psql_teller -f "${SQL_DIR}/teller_identity_address.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_identities.sql"
run_psql_teller -f "${SQL_DIR}/teller_routing_numbers.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_details_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_details.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_balances_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_account_balances.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_type.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_details_counterparty.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_links.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_details.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction.sql"
run_psql_teller -f "${SQL_DIR}/teller_nys_snw_category.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_nys_snw_category.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_email_match_run.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_email_candidate.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_email_match.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_email_match_audit.sql"
#R045: Ensure transaction classification FK cascades deletes from teller.transaction.
run_psql_teller -c \
"ALTER TABLE teller.transaction_nys_snw_category \
 DROP CONSTRAINT IF EXISTS transaction_nys_snw_category_transaction_id_fkey, \
 ADD CONSTRAINT transaction_nys_snw_category_transaction_id_fkey \
 FOREIGN KEY (transaction_id) REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE;"
#R040: Attach updated_at triggers only after all updated_at tables exist.
run_psql_teller -f "${SQL_DIR}/create_triggers.sql"
run_psql_teller -f "${SQL_DIR}/teller_transaction_info_view.sql"
run_psql_teller -f "${SQL_DIR}/create_audit.sql"
#R055: Apply explicit reconcile/audit grants for runtime ingest role.
run_psql_teller -f "${SQL_DIR}/grant_ingest_reconcile_privileges.sql"
