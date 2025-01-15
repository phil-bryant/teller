#!/bin/bash
set -e

read -p "Are you sure you want to destroy the database and all roles? This cannot be undone. Type 'destroy' to confirm: " confirmation

if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 1
fi

# Drop database and roles
psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS prod;"
psql -U postgres -d postgres -c "DROP USER IF EXISTS teller;"
psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_admin;"
psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_write;"
psql -U postgres -d postgres -c "DROP ROLE IF EXISTS teller_read;"

echo "Cleanup complete!" 