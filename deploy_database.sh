#!/bin/bash
set -e

# First we must use the admin user to create the prod database, teller schema, and tellerroles
psql -U postgres -f 00_create_database.sql
psql -U postgres -d prod -f 01_configure_database.sql

# Then we can use the teller user to create the teller tables in dependency order
for file in $(ls [0-9][0-9]_*.sql | sort -n | grep -v "^0[01]"); do
    echo "Running $file..."
    psql -U teller -d prod -f "$file"
done