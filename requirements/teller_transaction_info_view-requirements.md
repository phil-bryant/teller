# Transaction Info View Requirements

## Scope

Applies to `sql/postgres/teller_transaction_info_view.sql`.

## Ownership Boundaries

Deployment sequencing and invocation remain defined in `requirements/05_deploy_database-requirements.md`, and ORM/table naming contracts remain defined in `requirements/teller_object-requirements.md`.

R001  Statement: Provide a denormalized transaction reporting view across account and transaction-related tables.
Design: Define `teller.transaction_info_view` by joining `teller.transaction` with account, type, details, and counterparty tables and projecting reporting columns.
Tests:
- Query the view after loading representative data and verify joined columns resolve as expected.

R005  Statement: Return view rows in deterministic chronological order.
Design: Include `ORDER BY tt.date, tt.description` in the view definition.
Tests:
- Insert multiple rows with different dates/descriptions and verify view output ordering is stable.

## Changelog

- 2026-04-23: Added dedicated SQL requirements for `teller_transaction_info_view.sql`.
