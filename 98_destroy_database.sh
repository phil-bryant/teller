#!/bin/bash
#R001: Fail fast on unrecoverable teardown errors.
set -e

#R005: Configure 1psa source for postgres password lookup.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"

#R005: Require 1psa before credential lookup.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

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

#R010: Require explicit destroy confirmation.
read -r -p "Are you sure you want to destroy the database and all roles? This cannot be undone. Type 'destroy' to confirm: " confirmation

if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 1
fi

#R015: Clean dependent view and terminate sessions before database drop.
prod_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='prod';")"
if [ "$prod_exists" = "1" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d prod -c "DROP VIEW IF EXISTS teller.transaction_info_view;"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='prod' AND pid <> pg_backend_pid();"
fi
#R020: Drop database, user, and teller roles idempotently.
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS prod;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP USER IF EXISTS teller;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_admin;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_write;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_read;"

#R025: Print completion status after teardown.
echo "Cleanup complete!" 