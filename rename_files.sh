#!/bin/bash

# Rename SQL files from 09-13 to 08-12
mv 09_create_transaction_counterparties.sql 08_create_transaction_counterparties.sql
mv 10_create_transactions.sql 09_create_transactions.sql
mv 11_create_indexes.sql 10_create_indexes.sql
mv 12_create_triggers.sql 11_create_triggers.sql
mv 13_create_audit.sql 12_create_audit.sql

echo "Files have been renamed successfully" 