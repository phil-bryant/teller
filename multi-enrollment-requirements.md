# Multi Enrollment Requirements

## Scope

Applies to enrollment selection, CLI-targeted multi-enrollment execution, and Teller ingestion behavior for credit accounts.

## Assumptions

- Teller API remains the ingestion source for this phase.
- `institution_id` values follow Teller institution IDs (for example: `first_ak_bank_trust`, `chase`).
- Existing account/transaction persistence paths remain the system of record.
- Existing single-token users keep `~/.teller/auth_token.json` as the default credential path.

## Non-Goals (This Revision)

- No PDF statement ingestion in this revision.
- No new transaction schema dedicated only to credit cards.

## Requirements

R001  Statement: Accept optional `--institution_id <institution_id>` CLI flag.
Design: Add flag to the ingestion entrypoint and propagate it to enrollment selection logic.
Tests:
- Run with `--institution_id chase` and verify targeted selection path is used.

R005  Statement: Process all enrollments when `--institution_id` is omitted.
Design: Default selection is full enrollment set from enrollment metadata.
Tests:
- Run without the flag and verify all known enrollments are attempted.

R010  Statement: Keep `auth_token.json` as default credential source.
Design: Preserve current single-token execution when no multi-enrollment CLI input is provided.
Tests:
- Run without multi-enrollment arguments and verify current single-enrollment behavior remains unchanged.

R012  Statement: Auto-discover enrollment contexts without enrollment CLI inputs.
Design: Discover contexts from fixed local Teller paths (`auth_token.json`, `enrollment_id.txt`, optional metadata files).
Constraints:
- No enrollment file path CLI argument is required.
- Missing optional metadata must not fail the run.
Tests:
- Run with only default Teller files present and verify ingestion still runs.
- Add optional metadata files and verify contexts are auto-discovered.

R013  Statement: Require only `--institution_id` for targeted enrollment selection.
Design: Use `--institution_id` as the single targeting control and resolve matching enrollment contexts automatically.
Constraints:
- Exact match on institution id for explicit metadata contexts.
- If no explicit metadata match exists, fall back to default context and database-based inference.
Tests:
- Run with `--institution_id chase` and verify non-matching explicit contexts are skipped.
- Run with `--institution_id` where no explicit context exists and verify fallback still attempts ingestion.

R015  Statement: Select enrollments by exact `institution_id` match.
Design: Filter the full selected set (default plus CLI-targeted enrollments) before API calls.
Tests:
- Run with `--institution_id first_ak_bank_trust` and verify only matching enrollment(s) are executed.
- Run with unknown `--institution_id` and verify clean zero-work exit with message.

R020  Statement: Ingest Chase accounts through the existing Teller account flow.
Design: Reuse `/accounts`, `/identity`, `/transactions`, and `/balances` flow without a Chase-specific API client.
Tests:
- With `--institution_id chase`, verify account discovery completes with Teller endpoints only.

R025  Statement: Ingest Chase credit card transactions.
Design: Treat accounts with `type=credit` and `subtype=credit_card` as first-class ingestion targets.
Tests:
- Verify transactions for Chase credit card accounts are fetched and persisted.
- Verify mixed depository/credit institution runs persist both account categories.

R030  Statement: Keep per-enrollment failures isolated.
Design: Record enrollment-scoped errors and continue remaining selected enrollments.
Tests:
- Simulate one disconnected enrollment and verify others still complete.

R035  Statement: Define disconnected-enrollment handling for targeted runs.
Design: If a selected enrollment is disconnected, attempt repair using stored `enrollment_id`; fail that enrollment only on repair failure.
Tests:
- Run targeted institution with disconnected enrollment and verify repair attempt occurs once.

R040  Statement: Preserve backward compatibility for single-enrollment users.
Design: Existing one-token flow must still work without enrollment metadata bootstrapping or migration.
Tests:
- Fresh single-enrollment setup runs unchanged with no additional required args.

R045  Statement: Emit enrollment-scoped observability fields.
Design: Include `institution_id`, `enrollment_id`, account count, transaction count, and status per enrollment in logs.
Tests:
- Verify run output includes one completion line per enrollment with those fields.

## Acceptance Matrix

- `no flag` + default credential only -> default enrollment attempted and reported.
- `no flag` + auto-discovered contexts -> all discovered contexts are attempted and reported.
- `--institution_id chase` -> only Chase enrollment(s) attempted.
- `--institution_id first_ak_bank_trust` -> only First AK enrollment(s) attempted.
- `--institution_id unknown_bank` -> no enrollment attempts; deterministic message and success exit.
- Chase credit card account present -> transactions are fetched and persisted.

## Migration Notes

- No mandatory metadata migration is required.
- `auth_token.json` remains default and sufficient for single-enrollment operation.
- Multi-enrollment behavior is unlocked by automatic discovery from fixed local Teller files.

## Changelog

- 2026-04-13: Initial requirements for multi-enrollment selection and Chase credit-card ingestion (Teller API phase).
- 2026-04-13: Revised mapping to institution filter + CLI-targeted enrollments + Teller-only Chase ingestion.
- 2026-04-13: Replaced enrollment-file CLI model with auto-discovery + institution-id targeting only.
