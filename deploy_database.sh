#!/bin/bash
set -e
source ~/.env
export PGPASSWORD=$TELLER_POSTGRES_PASSWORD

## First we must use the admin user to create the teller database, teller schema, and tellerroles
psql -P pager=off -U postgres -f create_database.sql
psql -P pager=off -U postgres -d teller -v TELLER_POSTGRES_PASSWORD="$TELLER_POSTGRES_PASSWORD" -f configure_database.sql

## Then we can use the teller user to create the teller tables in dependency order
psql -P pager=off -U teller -d teller -f teller_enums.sql
psql -P pager=off -U teller -d teller -f teller_institution.sql
psql -P pager=off -U teller -d teller -f teller_account_links.sql
psql -P pager=off -U teller -d teller -f teller_account.sql
psql -P pager=off -U teller -d teller -f teller_identity.sql
psql -P pager=off -U teller -d teller -f teller_identity_name.sql
psql -P pager=off -U teller -d teller -f teller_identity_email.sql
psql -P pager=off -U teller -d teller -f teller_identity_phone_number.sql
psql -P pager=off -U teller -d teller -f teller_identity_address_data.sql
psql -P pager=off -U teller -d teller -f teller_identity_address.sql
psql -P pager=off -U teller -d teller -f teller_account_identities.sql
psql -P pager=off -U teller -d teller -f teller_routing_numbers.sql
psql -P pager=off -U teller -d teller -f teller_account_details_links.sql
psql -P pager=off -U teller -d teller -f teller_account_details.sql
psql -P pager=off -U teller -d teller -f teller_account_balances_links.sql
psql -P pager=off -U teller -d teller -f teller_account_balances.sql
psql -P pager=off -U teller -d teller -f teller_transaction_type.sql
psql -P pager=off -U teller -d teller -f teller_transaction_details_counterparty.sql
psql -P pager=off -U teller -d teller -f teller_transaction_links.sql
psql -P pager=off -U teller -d teller -f teller_transaction_details.sql
psql -P pager=off -U teller -d teller -f teller_transaction.sql
psql -P pager=off -U teller -d teller -f create_updated_at_triggers.sql
psql -P pager=off -U teller -d teller -f create_audit.sql

## Deploy table constraints view and function
psql -P pager=off -U teller -d teller -f all_table_constraints.sql
psql -P pager=off -U teller -d teller -f table_constraints.sql

unset PGPASSWORD