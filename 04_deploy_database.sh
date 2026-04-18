#!/bin/bash
set -e

POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
TELLER_PSA_ITEM="${TELLER_PSA_ITEM:-localhost_postgres_teller}"
TELLER_PSA_FIELD="${TELLER_PSA_FIELD:-password}"
SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sql/postgres"

if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

if [ "$TELLER_PSA_FIELD" = "password" ]; then
    TELLER_PASSWORD="$(1psa -p "$TELLER_PSA_ITEM")"
else
    TELLER_PASSWORD="$(1psa -f "$TELLER_PSA_ITEM" "$TELLER_PSA_FIELD")"
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

if [ -z "$TELLER_PASSWORD" ]; then
    echo "Failed to read teller password from 1psa item: $TELLER_PSA_ITEM"
    exit 1
fi

# First we must use the admin user to create the prod database, teller schema, and tellerroles
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -f "${SQL_DIR}/create_database.sql"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d prod -v teller_password="$TELLER_PASSWORD" -f "${SQL_DIR}/configure_database.sql"

# Then we can use the teller user to create the teller tables in dependency order
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_enums.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_institution.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account_links.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_identity.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_identity_name.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_identity_email.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_identity_phone_number.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_identity_address_data.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_identity_address.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account_identities.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_routing_numbers.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account_details_links.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account_details.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account_balances_links.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_account_balances.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_type.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_details_counterparty.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_links.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_details.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/create_triggers.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/create_audit.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_nys_snw_category.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_nys_snw_category.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_info_view.sql"

