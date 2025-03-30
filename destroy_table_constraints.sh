#!/bin/bash
set -e
source ~/.env
export PGPASSWORD=$TELLER_POSTGRES_PASSWORD

read -p "Are you sure you want to drop the table constraints function and view? Type 'drop' to confirm: " confirmation
if [ "$confirmation" != "drop" ]; then
    echo "Operation cancelled"
    exit 1
fi

## Drop table constraints function and view
psql -P pager=off -U postgres -d teller -c "DROP FUNCTION IF EXISTS table_constraints(text, text);"
psql -P pager=off -U postgres -d teller -c "DROP VIEW IF EXISTS teller.all_table_constraints;"

echo "Table constraints dropped successfully!"
unset PGPASSWORD
