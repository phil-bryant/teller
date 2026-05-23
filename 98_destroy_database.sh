#!/bin/bash
#R001: Fail fast on unrecoverable teardown errors.
set -e

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# Resolve the active DB profile so we know whether to tear down a local DB or a managed schema.
DB_PROFILE_HELPER="${SCRIPT_DIR}/scripts/db_profile_export.sh"

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
profile_exports_file="$(mktemp)"
if ! "$DB_PROFILE_HELPER" >"$profile_exports_file"; then
    rm -f "$profile_exports_file"
    exit 1
fi
PROFILE_EXPORTS="$(<"$profile_exports_file")"
rm -f "$profile_exports_file"
eval "$PROFILE_EXPORTS"

# Ensure psql stops immediately on SQL errors.
PSQL_OPTS=(-v ON_ERROR_STOP=1)

if [[ "${PROFILE_TARGET:-local}" == "managed" ]]; then
    # Re-resolve using the direct (non-pooler) profile for DDL teardown.
    if [[ "$PROFILE_NAME" != "supabase_direct" && -x "$DB_PROFILE_HELPER" ]]; then
        profile_exports_file="$(mktemp)"
        if ! "$DB_PROFILE_HELPER" --profile supabase_direct >"$profile_exports_file"; then
            rm -f "$profile_exports_file"
            exit 1
        fi
        PROFILE_EXPORTS="$(<"$profile_exports_file")"
        rm -f "$profile_exports_file"
        eval "$PROFILE_EXPORTS"
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
            echo "Managed destroy requires PG_ONEPSA_ITEM (from db-profiles.json) or TELLER_DB_PASSWORD."
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
    SCHEMA_NAME="${PG_SEARCH_PATH:-teller}"
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
LOCAL_DBNAME="${PG_DBNAME:-prod}"

echo "ℹ️  Destroying local database via profile=${PROFILE_NAME:-local} db=${LOCAL_DBNAME}"

#R010: Require explicit destroy confirmation.
read -r -p "Are you sure you want to destroy database '${LOCAL_DBNAME}' and all teller roles? This cannot be undone. Type 'destroy' to confirm: " confirmation

if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 1
fi

#R015: Clean dependent view and terminate sessions before database drop.
db_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${LOCAL_DBNAME}';")"
if [ "$db_exists" = "1" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d "$LOCAL_DBNAME" -c "DROP VIEW IF EXISTS teller.transaction_info_view;"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${LOCAL_DBNAME}' AND pid <> pg_backend_pid();"
fi
#R020: Drop database, user, and teller roles idempotently.
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS \"${LOCAL_DBNAME}\";"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP USER IF EXISTS teller;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_admin;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_write;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_read;"

#R025: Print completion status after teardown.
echo "Cleanup complete!"
