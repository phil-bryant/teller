#!/bin/bash
#R001: Fail fast on unrecoverable SQL/bootstrap errors.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R035: Resolve SQL directory relative to script location.
SQL_DIR="${SCRIPT_DIR}/sql/postgres"
#R060: Resolve the active DB profile so we know whether to deploy locally or to a managed target.
DB_PROFILE_HELPER="${SCRIPT_DIR}/scripts/db_profile_export.sh"

#R005: Require 1psa before credential lookups.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

#R060: Read the resolved profile via the shared helper. For managed targets we force the
#R060: "supabase_direct" profile so DDL never goes through the transaction pooler.
if [[ -x "$DB_PROFILE_HELPER" ]]; then
    eval "$("$DB_PROFILE_HELPER")"
else
    PROFILE_NAME="local"
    PROFILE_TARGET="local"
fi

#R060: Print the resolved deploy target so the operator sees where deploy is running.
echo "ℹ️  Deploying database via profile=${PROFILE_NAME} target=${PROFILE_TARGET}${PG_HOST:+ host=${PG_HOST}}${PG_PORT:+ port=${PG_PORT}}${PG_DBNAME:+ db=${PG_DBNAME}}${PG_USER:+ user=${PG_USER}}"

#R006: Ensure psql stops immediately on SQL errors.
PSQL_OPTS=(-v ON_ERROR_STOP=1)

if [[ "${PROFILE_TARGET:-local}" == "managed" ]]; then
    #R060: Re-resolve using the direct (non-pooler) profile for DDL apply.
    if [[ "$PROFILE_NAME" != "supabase_direct" && -x "$DB_PROFILE_HELPER" ]]; then
        eval "$("$DB_PROFILE_HELPER" --profile supabase_direct)"
        echo "ℹ️  Switched to direct DDL profile=${PROFILE_NAME} host=${PG_HOST} port=${PG_PORT} db=${PG_DBNAME} user=${PG_USER}"
    fi

    #R065: Resolve managed-target password from the profile's 1psa item; env var still wins.
    MANAGED_PASSWORD="${TELLER_DB_PASSWORD:-}"
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        if [[ -z "${PG_PASSWORD_PSA_ITEM:-}" ]]; then
            echo "Managed deploy requires PG_PASSWORD_PSA_ITEM (from db-profiles.json) or TELLER_DB_PASSWORD."
            exit 1
        fi
        MANAGED_PASSWORD="$(1psa -p "$PG_PASSWORD_PSA_ITEM")"
    fi
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        echo "Failed to read managed DB password (item: ${PG_PASSWORD_PSA_ITEM})"
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
    PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres "$@"
}

#R008: Run SQL as teller with fail-fast psql options.
run_psql_teller() {
    PGPASSWORD="$TELLER_PASSWORD" psql "${PSQL_OPTS[@]}" -U teller -d prod "$@"
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
#R085: Skip create_database.sql when 'prod' already exists so re-runs against an existing local DB
#R085: do not error. configure_database.sql is now idempotent on its own.
prod_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='prod'")"
if [ -z "$prod_exists" ]; then
    run_psql_postgres -f "${SQL_DIR}/create_database.sql"
fi
run_psql_postgres -d prod -v teller_password="$TELLER_PASSWORD" -f "${SQL_DIR}/configure_database.sql"
#R050: Ensure pgTAP extension exists in prod for SQL unit test execution.
run_psql_postgres -d prod -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

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
