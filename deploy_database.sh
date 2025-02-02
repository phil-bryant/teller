#!/bin/bash
set -e

# First we must use the admin user to create the prod database, teller schema, and tellerroles
psql -U postgres -f create_database.sql
psql -U postgres -d prod -f configure_database.sql

# Then we can use the teller user to create the teller tables in dependency order
psql -U teller -d prod -f teller_enums.sql
psql -U teller -d prod -f teller_institution.sql
psql -U teller -d prod -f teller_account.sql
psql -U teller -d prod -f teller_address_data.sql
psql -U teller -d prod -f teller_counterparty.sql
psql -U teller -d prod -f teller_transaction_counterparty.sql
psql -U teller -d prod -f teller_transaction.sql
psql -U teller -d prod -f teller_identity.sql
psql -U teller -d prod -f teller_address.sql
psql -U teller -d prod -f teller_email.sql
psql -U teller -d prod -f teller_name.sql
psql -U teller -d prod -f teller_phone_number.sql
psql -U teller -d prod -f teller_routing_numbers.sql
psql -U teller -d prod -f teller_account_details.sql
psql -U teller -d prod -f teller_account_identities.sql
psql -U teller -d prod -f teller_balances.sql
psql -U teller -d prod -f teller_account_balances_links.sql
psql -U teller -d prod -f teller_account_details_links.sql
psql -U teller -d prod -f teller_account_links.sql
psql -U teller -d prod -f teller_transaction_details.sql
psql -U teller -d prod -f teller_transaction_links.sql
psql -U teller -d prod -f create_identity_relationships.sql
psql -U teller -d prod -f create_indexes.sql
psql -U teller -d prod -f create_triggers.sql
psql -U teller -d prod -f create_audit.sql