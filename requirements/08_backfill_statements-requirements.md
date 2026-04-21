# Backfill Statements Requirements

## Scope

Applies to `08_backfill_statements.py`.

R001  Statement: OCR statement PDFs into normalized page text.
Design: Render PDF pages to images and run Vision OCR via Swift bridge for line reconstruction.
Tests:
- Provide sample PDF and verify OCR pipeline returns one text block per page.

R005  Statement: Parse statement metadata and transactions from OCR pages.
Design: Extract statement date/summary totals and parse grouped transaction lines with signed amounts and inferred types.
Tests:
- Parse fixture pages and verify expected transaction count, dates, and signed amounts.

R010  Statement: Match each statement to the correct teller account.
Design: Resolve account from explicit override, single-account shortcut, or inferred last-four hints.
Tests:
- With multi-account institution and last-four hint, verify account match selection.

R015  Statement: Persist backfilled transactions with deterministic statement IDs.
Design: Build `stmt_` hash IDs, skip dates after earliest API transaction, and upsert via persistence helper.
Tests:
- Verify generated IDs are stable for same transaction tuple and occurrence index.

R020  Statement: Support scoped and non-destructive CLI execution modes.
Design: Implement `--institution-id`, `--account-id`, `--statements-root`, and `--dry-run` controls.
Tests:
- Run with `--dry-run` and verify database writes are skipped.

R025  Statement: Emit audit logs for parsing quality and completion summary.
Design: Log parsed totals, mismatch warnings, commit events, and final inserted/skipped counters.
Tests:
- Verify completion log includes inserted, skipped, and total parsed counts.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `08_backfill_statements.py`.
- 2026-04-20: Reviewed multi-enrollment requirements; no additional enrollment-selection or Connect-UI requirements apply here.
