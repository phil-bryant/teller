#!/usr/bin/env bash
#R001: Fail fast on unrecoverable teardown errors.
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# Resolve the active DB profile so we know whether to tear down a local DB or a managed schema.
DB_PROFILE_HELPER="${SCRIPT_DIR}/src/scripts/db_profile_export.sh"
#R005: Require 1psa before any credential lookup.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

# Read the resolved profile via the shared helper. For managed targets we force the
# "supabase_direct" profile so DDL never goes through the transaction pooler.
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
            if (key !~ /^(DB_DIALECT|PROFILE_NAME|PROFILE_TARGET|PG_HOST|PG_PORT|PG_DBNAME|PG_USER|PG_SSLMODE|PG_SEARCH_PATH|PG_RUNTIME_ROLE|PG_ONEPSA_ITEM|SQLITE_PATH)$/) {
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
    unset PG_SSLMODE PG_SEARCH_PATH PG_RUNTIME_ROLE PG_ONEPSA_ITEM SQLITE_PATH
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
    require_nonempty_env "Profile resolution" PG_DBNAME
fi
PG_SSLMODE="${PG_SSLMODE:-}"

# Ensure psql stops immediately on SQL errors.
PSQL_OPTS=(-v ON_ERROR_STOP=1)

#R026: Support SQLite teardown through the existing destroy entrypoint.
if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
    SQLITE_DB_PATH="${SQLITE_PATH:-}"
    if [[ -z "$SQLITE_DB_PATH" ]]; then
        echo "SQLite destroy requires SQLITE_PATH from db profile export."
        exit 1
    fi
    read -r -p "Are you sure you want to destroy sqlite database '${SQLITE_DB_PATH}'? This cannot be undone. Type 'destroy' to confirm: " confirmation
    if [ "$confirmation" != "destroy" ]; then
        echo "Destruction cancelled"
        exit 1
    fi
    rm -f "$SQLITE_DB_PATH"
    echo "Cleanup complete!"
    exit 0
fi

if [[ "${PROFILE_TARGET:-local}" == "managed" ]]; then
    # Re-resolve using the direct (non-pooler) profile for DDL teardown.
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
    fi
    require_nonempty_env "Managed destroy profile" PROFILE_NAME PG_HOST PG_PORT PG_DBNAME PG_USER PG_SEARCH_PATH
    if [[ "$PG_SEARCH_PATH" == "public" || "$PG_SEARCH_PATH" == "pg_catalog" || "$PG_SEARCH_PATH" == "information_schema" ]]; then
        echo "Refusing to destroy managed schema '${PG_SEARCH_PATH}'. Choose an explicit app schema."
        exit 1
    fi

    echo "ℹ️  Destroying managed schema via profile=${PROFILE_NAME} host=${PG_HOST} port=${PG_PORT} db=${PG_DBNAME} user=${PG_USER} schema=${PG_SEARCH_PATH}"

    #R010: Require explicit destroy confirmation.
    read -r -p "Are you sure you want to drop schema ${PG_SEARCH_PATH} and teller roles on ${PG_HOST}? This cannot be undone. Type 'destroy' to confirm: " confirmation
    if [ "$confirmation" != "destroy" ]; then
        echo "Destruction cancelled"
        exit 1
    fi

    # Resolve managed-target password from the profile's 1psa item; env var still wins.
    MANAGED_PASSWORD="${TELLER_DB_PASSWORD:-}"
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        if [[ -z "${PG_ONEPSA_ITEM:-}" ]]; then
            echo "Managed destroy requires PG_ONEPSA_ITEM (from config/db-profiles.json) or TELLER_DB_PASSWORD."
            exit 1
        fi
        MANAGED_PASSWORD="$(1psa -p "$PG_ONEPSA_ITEM")"
    fi
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        echo "Failed to read managed DB password (item: ${PG_ONEPSA_ITEM})"
        exit 1
    fi

    # Run SQL against the managed target as the profile user.
    run_psql_managed() {
        PGPASSWORD="$MANAGED_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql "${PSQL_OPTS[@]}" \
            -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DBNAME" "$@"
    }

    # Preflight: confirm the host resolves and we can connect before sending any DROP.
    # Catches AAAA-only hosts (e.g. legacy db.<ref>.supabase.co) and bad creds up front.
    if ! getent hosts "$PG_HOST" >/dev/null 2>&1 && ! host -t A "$PG_HOST" >/dev/null 2>&1; then
        if ! host "$PG_HOST" >/dev/null 2>&1; then
            echo "❌ Cannot resolve host '$PG_HOST'."
            echo "   Supabase is deprecating direct db.<ref>.supabase.co hosts; switch the"
            echo "   EGGNEST_SUPABASE_DIRECT 1psa item to the Session pooler connection"
            echo "   (host: aws-0-<region>.pooler.supabase.com, port: 5432, user: postgres.<ref>)."
            exit 1
        fi
    fi
    if ! preflight_err="$(PGPASSWORD="$MANAGED_PASSWORD" PGSSLMODE="$PG_SSLMODE" psql "${PSQL_OPTS[@]}" \
        -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DBNAME" -tAc "SELECT 1;" 2>&1 >/dev/null)"; then
        echo "❌ Could not connect to ${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DBNAME}. No DROP statements were sent."
        echo "   psql said: ${preflight_err}"
        exit 1
    fi

    # On managed targets we cannot DROP DATABASE; drop the teller schema and teller roles only.
    #R032: Validate managed schema identifier before destructive schema drop.
    SCHEMA_NAME="${PG_SEARCH_PATH:-teller}"
    if ! is_valid_pg_identifier "$SCHEMA_NAME"; then
        echo "Refusing to destroy invalid schema identifier: ${SCHEMA_NAME}"
        exit 1
    fi
    #R033: Identifier already validated; execute DROP SCHEMA directly for psql -c compatibility.
    run_psql_managed -c "DROP SCHEMA IF EXISTS \"${SCHEMA_NAME}\" CASCADE;"
    # Drop teller roles idempotently. Order matters: drop dependent roles before parents.
    run_psql_managed -c "DROP ROLE IF EXISTS teller_write;"
    run_psql_managed -c "DROP ROLE IF EXISTS teller_read;"
    run_psql_managed -c "DROP ROLE IF EXISTS teller_admin;"
    # Drop the teller user last so any remaining dependencies surface as a clear error.
    run_psql_managed -c "DROP USER IF EXISTS teller;"

    #R025: Print completion status after teardown.
    echo "Cleanup complete!"
    exit 0
fi

#R005: Configure 1psa source for postgres password lookup.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"

#R005: Resolve postgres password from configured 1psa item/field.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

#R005: Refuse teardown when password lookup is empty.
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

# Use the resolved profile's DB name when available so a non-default local DB still works.
require_nonempty_env "Local destroy profile" PG_DBNAME
#R030: Validate local DB identifier before local teardown SQL executes.
LOCAL_DBNAME="$PG_DBNAME"
if ! is_valid_pg_identifier "$LOCAL_DBNAME"; then
    echo "Refusing to destroy invalid database identifier: ${LOCAL_DBNAME}"
    exit 1
fi

echo "ℹ️  Destroying local database via profile=${PROFILE_NAME:-local} db=${LOCAL_DBNAME}"

#R010: Require explicit destroy confirmation.
read -r -p "Are you sure you want to destroy database '${LOCAL_DBNAME}' and all teller roles? This cannot be undone. Type 'destroy' to confirm: " confirmation

if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 1
fi

#R015: Clean dependent view and terminate sessions before database drop.
#R031: Identifier already validated; use direct SQL compatible with psql -c.
db_exists="$(
    PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres \
        -tAc "SELECT 1 FROM pg_database WHERE datname = '${LOCAL_DBNAME}';"
)"
if [ "$db_exists" = "1" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d "$LOCAL_DBNAME" -c "DROP VIEW IF EXISTS teller.transaction_info_view;"
    PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${LOCAL_DBNAME}' AND pid <> pg_backend_pid();"
fi
#R020: Drop database, user, and teller roles idempotently.
#R031: Identifier already validated; execute DROP DATABASE directly.
PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres \
    -c "DROP DATABASE IF EXISTS \"${LOCAL_DBNAME}\";"
PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres -c "DROP USER IF EXISTS teller;"
PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_admin;"
PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_write;"
PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_read;"

#R025: Print completion status after teardown.
echo "Cleanup complete!"
