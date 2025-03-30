#!/bin/bash
set -e
source ~/.env
export PGPASSWORD=$TELLER_POSTGRES_PASSWORD

## Deploy table constraints view and function
psql -P pager=off -U teller -d teller -f all_table_constraints.sql
psql -P pager=off -U teller -d teller -f table_constraints.sql

echo "Table constraints deployed successfully!"
unset PGPASSWORD
