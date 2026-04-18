#!/bin/bash
set -e

# Rename files
mv_if_exists() {
    if [ -f "$1" ]; then
        echo "Renaming $1 to $2"
        mv "$1" "$2"
    else
        echo "Warning: $1 not found"
    fi
}

mv_if_exists "00_create_database.sql" "create_database.sql"
mv_if_exists "01_configure_database.sql" "configure_database.sql"
mv_if_exists "02_teller_enums.sql" "teller_enums.sql"
mv_if_exists "03_teller_institution.sql" "teller_institution.sql"
mv_if_exists "04_teller_account.sql" "teller_account.sql"
mv_if_exists "05_teller_address_data.sql" "teller_address_data.sql"
mv_if_exists "06_teller_counterparty.sql" "teller_counterparty.sql"
mv_if_exists "07_teller_transaction_counterparty.sql" "teller_transaction_counterparty.sql"
mv_if_exists "08_teller_transaction.sql" "teller_transaction.sql"
mv_if_exists "09_teller_identity.sql" "teller_identity.sql"
mv_if_exists "10_teller_address.sql" "teller_address.sql"
mv_if_exists "11_teller_email.sql" "teller_email.sql"
mv_if_exists "12_teller_name.sql" "teller_name.sql"
mv_if_exists "13_teller_phone_number.sql" "teller_phone_number.sql"
mv_if_exists "14_teller_routing_numbers.sql" "teller_routing_numbers.sql"
mv_if_exists "15_teller_account_details.sql" "teller_account_details.sql"
mv_if_exists "16_teller_account_identities.sql" "teller_account_identities.sql"
mv_if_exists "17_teller_balances.sql" "teller_balances.sql"
mv_if_exists "18_teller_account_balances_links.sql" "teller_account_balances_links.sql"
mv_if_exists "19_teller_account_details_links.sql" "teller_account_details_links.sql"
mv_if_exists "20_teller_account_links.sql" "teller_account_links.sql"
mv_if_exists "21_teller_transaction_details.sql" "teller_transaction_details.sql"
mv_if_exists "22_teller_transaction_links.sql" "teller_transaction_links.sql"
mv_if_exists "23_create_identity_relationships.sql" "create_identity_relationships.sql"
mv_if_exists "24_create_indexes.sql" "create_indexes.sql"
mv_if_exists "25_create_triggers.sql" "create_triggers.sql"
mv_if_exists "26_create_audit.sql" "create_audit.sql"