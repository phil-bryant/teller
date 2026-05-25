# Teller Persist Requirements

## Scope

Applies to `src/teller/teller_persist.py`.

R001  Statement: Execute persistence queries through shared SQL helpers.
Design: `_exec` executes SQL text with optional params; `_exec_returning` executes and returns a single row for insert/update-returning flows.
Tests:
- R001-T01: Run helper calls against a test session and verify parameterized statements execute and returning rows are accessible.

R005  Statement: Upsert account-level Teller entities idempotently.
Design: Upsert institution, account links, and account rows using conflict handling while preserving existing link row IDs when updating.
Tests:
- R005-T01: Persist the same account payload twice and verify one logical account row remains with updated mutable fields.

R010  Statement: Upsert identity graph and account-to-identity links without duplication.
Design: Reuse identity by matching known email rows when present; upsert names/emails/phones/addresses and link identities to accounts via `account_identities`.
Tests:
- R010-T01: Persist repeated owner payloads and verify identity rows are reused/updated rather than duplicated.
- R010-T02: Verify account-identity link insert is conflict-safe.

R015  Statement: Upsert transactions with normalized relation rows and numeric casting.
Design: Upsert transaction type, details, links, and transaction rows; cast `amount` and optional `running_balance` to `Decimal`.
Tests:
- R015-T01: Persist transaction payload with links/details and verify relational rows and transaction row are written.
- R015-T02: Re-persist with changed mutable fields and verify transaction conflict update path applies.

R020  Statement: Canonicalize duplicate fetched transaction snapshots by transaction ID.
Design: `_canonicalize_transactions` deduplicates by ID and prefers incoming `posted` snapshots over existing `pending` snapshots.
Tests:
- R020-T01: Provide duplicate IDs with mixed statuses and verify canonical output keeps the posted variant.

R025  Statement: Reconcile stale pending transactions absent from the latest fetch.
Design: `_reconcile_missing_pending_transactions` deletes pending rows for an account when IDs are missing from fetched set (or all pending when fetched set is empty) and returns deleted IDs.
Tests:
- R025-T01: Persist pending transactions, fetch a reduced set, and verify missing pending rows are deleted.
- R025-T02: Pass empty fetched IDs and verify all pending transactions for the account are removed.

R030  Statement: Prune unreferenced transaction relation rows after reconciliation.
Design: `_prune_unreferenced_transaction_relations` deletes orphaned rows from `transaction_links`, `transaction_details`, and `transaction_details_counterparty`, and reports counts.
Tests:
- R030-T01: Delete transactions that leave relation rows orphaned and verify orphan pruning removes only unreferenced rows.

R035  Statement: Persist account balance snapshots with upsert behavior.
Design: Upsert account-balance links and account-balance rows per account, with optional `ledger`/`available` cast to `Decimal` and timestamp refresh on updates.
Tests:
- R035-T01: Persist balances for an account and verify insert path writes links and balances.
- R035-T02: Re-persist with updated balances and verify update path and timestamp refresh.

R040  Statement: Persist account identities, balances, and transactions in one orchestrated commit.
Design: `persist_all` iterates identities, optional balances, and per-account transactions; applies canonicalization/reconciliation/pruning and commits once at the end with operational logging.
Tests:
- R040-T01: Run `persist_all` with representative payloads and verify all data domains are persisted and committed.
- R040-T02: Verify `raw_balances_by_account` is optional and does not block persistence when omitted.

## Changelog

- 2026-04-22: Initial reverse-engineered requirements for `src/teller/teller_persist.py`.
