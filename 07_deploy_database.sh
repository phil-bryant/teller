#!/bin/bash
#R001: Fail fast on unrecoverable SQL/bootstrap errors.
set -e

#R010: Configurable 1psa source for postgres admin password.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
#R015: Configurable 1psa source for teller user password.
TELLER_PSA_ITEM="${TELLER_PSA_ITEM:-localhost_postgres_teller}"
TELLER_PSA_FIELD="${TELLER_PSA_FIELD:-password}"
#R035: Resolve SQL directory relative to script location.
SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sql/postgres"

#R006: Ensure psql stops immediately on SQL errors.
PSQL_OPTS=(-v ON_ERROR_STOP=1)

#R007: Run SQL as postgres with fail-fast psql options.
run_psql_postgres() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql "${PSQL_OPTS[@]}" -U postgres "$@"
}

#R008: Run SQL as teller with fail-fast psql options.
run_psql_teller() {
    PGPASSWORD="$TELLER_PASSWORD" psql "${PSQL_OPTS[@]}" -U teller -d prod "$@"
}

#R005: Require 1psa before credential lookups.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

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
run_psql_postgres -f "${SQL_DIR}/create_database.sql"
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

