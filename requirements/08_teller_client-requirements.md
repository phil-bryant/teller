# Teller Client Requirements

## Scope

Applies to `08_teller_client.py`.

R001  Statement: Configure CLI behavior and log level from runtime flags.
Design: Parse `--debug`, `--dry-run`, and optional `--institution_id`; configure structlog by debug flag.
Tests:
- Run with `--debug` and verify debug logger configuration path executes.
- Run with `--institution_id chase` and verify institution-scoped selection path executes.

R005  Statement: Load Teller auth and TLS inputs from local teller directory.
Design: Read auth token from context token or `~/.teller/auth_token.json`; use cert/key under `~/.teller`.
Tests:
- Run with no explicit token and verify token file loading path is used.
- Run without context token overrides and verify default single-token behavior remains unchanged.

R010  Statement: Retry disconnected enrollments through local repair flow.
Design: Detect `enrollment.disconnected*`, launch local repair using selected `enrollment_id`, reload auth, and retry once.
Tests:
- Simulate disconnected response and verify repair flow attempts retry.
- Simulate failed repair and verify only that enrollment context fails.

R015  Statement: Fetch full transaction history via Teller pagination.
Design: Request transaction pages with `from_id` cursor until API returns empty page.
Tests:
- Mock paginated responses and verify page loop aggregates all transactions.
- Run with unknown `--institution_id` and verify no matching-account data is emitted.

R020  Statement: Build enrollment contexts from default, metadata, and suffixed token sources.
Design: Auto-discover contexts, merge/dedupe rows, and use `--institution_id` as the only targeting control.
Constraints:
- No enrollment file path CLI argument is required.
- Exact institution-id match is used for explicit contexts.
- If explicit context matches are absent, fall back to default contexts and DB enrollment-id inference.
Tests:
- Provide overlapping contexts and verify dedupe keeps one entry per key.
- Run with only default Teller files and verify ingestion still runs.
- Add metadata/suffix contexts and verify auto-discovery includes them.

R025  Statement: Persist fetched Teller objects unless dry-run is enabled.
Design: Iterate selected enrollment contexts, isolate per-enrollment failures, and persist merged Teller account data.
Constraints:
- Per-enrollment failures must not stop remaining selected enrollments.
- Deposits and credit-card account categories are both processed via the same Teller flow.
- Enrollment-scoped failure output includes `institution_id`, `enrollment_id`, status code, and message.
Tests:
- Run with `--dry-run` and verify no persistence call path is taken.
- Simulate one failing enrollment and verify other selected enrollments continue.

R030  Statement: Canonicalize duplicate transaction IDs during persistence so status transitions are durable.
Design: Before writing account transactions, dedupe by transaction ID and prefer `posted` snapshots over `pending`; then upsert all mutable transaction columns.
Tests:
- Feed duplicate transaction IDs with mixed statuses and verify the stored row ends as `posted`.
- Verify transaction upsert conflict updates refresh links/details/type/status fields on reruns.

R035  Statement: Prune unreferenced transaction relation rows after transaction reconciliation.
Design: After stale pending transaction deletion, remove unreferenced rows from `transaction_links`, `transaction_details`, and `transaction_details_counterparty`.
Tests:
- Delete stale transactions and verify unreferenced link/detail/counterparty rows are removed in the same persistence run.
- Verify referenced relation rows are preserved.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `08_teller_client.py`.
- 2026-04-20: Merged ingestion-side multi-enrollment requirements from `multi-enrollment-requirements.md`.
- 2026-04-22: Added duplicate-transaction canonicalization requirement to preserve pending-to-posted updates.
- 2026-04-22: Added R035 to prune unreferenced transaction relation rows after stale pending cleanup.
