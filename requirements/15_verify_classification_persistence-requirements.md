# Verify Classification Persistence Requirements

## Scope

Applies to `15_verify_classification_persistence.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `zsh` shebang and `set -euo pipefail`.
Tests:
- R001-T01: Cause command failure and verify script exits non-zero.

R005  Statement: Auto-resolve identifiers when env vars are missing.
Design: When `TXN_ID` and/or `CATEGORY_ID` are unset, query DB defaults from posted rows in `teller.transaction` and from `teller.nys_snw_category`.
Design: If either query returns no row, fail with actionable guidance instead of a generic parameter expansion error.
Tests:
- R005-T01: Run without `TXN_ID` and verify script auto-selects one from `status='posted'` transactions.
- R005-T02: Run without `CATEGORY_ID` and verify script auto-selects one.
- R005-T03: Run with empty `teller.transaction` and verify explicit guidance to load data or pass `TXN_ID`.

R006  Statement: Support strict env-only identifier mode.
Design: `--require-env-ids` enforces required parameter expansion for `TXN_ID` and `CATEGORY_ID`.
Tests:
- R006-T01: Run with `--require-env-ids` and missing `TXN_ID` to verify immediate failure.
- R006-T02: Run with `--require-env-ids` and missing `CATEGORY_ID` to verify immediate failure.

R010  Statement: Support configurable API endpoint and database connection defaults.
Design: Use `TELLER_CLASSIFIER_API_URL` and `TELLER_DB_*` overrides with localhost defaults.
Tests:
- R010-T01: Override API URL and verify request targets override.

R015  Statement: Resolve DB password from environment or 1psa fallback.
Design: Use `TELLER_DB_PASSWORD` when set, otherwise read from 1psa item.
Tests:
- R015-T01: Unset DB password and verify fallback 1psa lookup is used.

R020  Statement: Post classification update request to classifier API.
Design: Send JSON payload to `/v1/transactions/classifications` with provided IDs and include `X-Teller-Write-Token` resolved from env or 1psa fallback.
Tests:
- R020-T01: Verify request body includes provided transaction and category identifiers.
- R020-T02: Verify request headers include `X-Teller-Write-Token`.

R035  Statement: Resolve classifier write token from env or 1psa fallback.
Design: Use `TELLER_CLASSIFIER_WRITE_TOKEN` when set, otherwise read token via `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN`, and fail fast on missing/empty values before API mutation request.
Tests:
- R035-T01: Stub empty token lookup and verify script exits non-zero before curl mutation call.

R025  Statement: Query latest persisted classification for the target transaction.
Design: Execute `psql` query ordered by `updated_at DESC LIMIT 1`.
Tests:
- R025-T01: Verify output line is `<transaction_id>:<nys_snw_category_id>:<type>`.

R030  Statement: Print explicit pass/fail verification result.
Design: Print a `✅ PASS:` line when persisted value matches expected `<TXN_ID>:<CATEGORY_ID>:user`.
Design: Print a `❌ FAIL:` line and exit non-zero on API failure, mismatch, or missing persisted row.
Design: Always print API response and persisted-row details before pass/fail status.
Tests:
- R030-T01: On matching persisted classification, verify output starts with `✅ PASS:`.
- R030-T02: On mismatch or empty persisted row, verify output starts with `❌ FAIL:` and script exits non-zero.
- R030-T03: On API request failure, verify output starts with `❌ FAIL:` and script exits non-zero.
- R030-T04: On all outcomes after API call, verify output includes `API response:` and `Persisted row:` detail lines.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `15_verify_classification_persistence.sh`.
- 2026-04-20: Made smart identifier auto-resolution the default and added `--require-env-ids` strict mode.
- 2026-04-21: Added explicit, actionable failure behavior when auto-resolve queries return no rows.
- 2026-04-21: Added explicit `PASS:`/`FAIL:` result output with non-zero failures for API or persistence mismatch.
- 2026-04-21: Restored detailed output (API response + persisted row) while keeping icon pass/fail status lines.
- 2026-05-09: Added R035 and updated R020 for mandatory 1psa-only classifier write-token header usage.
