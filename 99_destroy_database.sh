#!/bin/bash
set -e

POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"

if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

read -p "Are you sure you want to destroy the database and all roles? This cannot be undone. Type 'destroy' to confirm: " confirmation

if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 1
fi

# Drop database and roles
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS prod;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP USER IF EXISTS teller;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_admin;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_write;"
PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_read;"

echo "Cleanup complete!" 