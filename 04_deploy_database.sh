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
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -f "${SQL_DIR}/create_database.sql"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d prod -v teller_password="$TELLER_PASSWORD" -f "${SQL_DIR}/configure_database.sql"

#R030: Build teller schema objects in declared dependency order.
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
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_nys_snw_category.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_nys_snw_category.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/teller_transaction_info_view.sql"
PGPASSWORD="$TELLER_PASSWORD" psql -U teller -d prod -f "${SQL_DIR}/create_audit.sql"

