# SQLite Create Database Requirements

## Scope

Applies to `src/sql/sqlite/create_database.sql`.

R001  Statement: SQLite deploy enables foreign-key enforcement before schema creation.
Design: `create_database.sql` starts with `PRAGMA foreign_keys = ON;` so SQLite follows relational FK semantics expected by runtime workflows.
Tests:
- R001-T01: Parse `create_database.sql` and verify the foreign-key pragma is present.

R005  Statement: SQLite deploy defines the core institution/account/identity graph required by ingest.
Design: `create_database.sql` creates institution/account/account_links plus identity tables and account linkage tables with stable names used by persistence SQL.
Tests:
- R005-T01: Parse `create_database.sql` and verify core ingest table names are declared.

R010  Statement: SQLite deploy defines transaction, classification, and match-review tables required by classification API runtime.
Design: `create_database.sql` creates transaction, category, mapping, and match-review tables with constraint intent equivalent to PostgreSQL workflow. SQLite money columns (`transaction.amount`, `transaction.running_balance`, `account_balances.ledger`, `account_balances.available`) are stored as integer minor units (cents) to avoid floating-point drift; current architecture assumes Teller account currency is USD.
Tests:
- R010-T01: Parse `create_database.sql` and verify classification + match-review table declarations exist.

R015  Statement: SQLite deploy materializes transaction list view required by verification and runtime queries.
Design: `create_database.sql` defines `transaction_info_view` joining transactions with latest category mapping shape expected by deploy verification.
Tests:
- R015-T01: Parse `create_database.sql` and verify `transaction_info_view` DDL is present.

## Changelog

- 2026-05-30: Added SQLite create-database SQL requirements for file-backed deploy path.
