# Verify Reclassification Persistence Requirements

## Scope

Applies to `11_verify_reclassification_persistence.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `zsh` shebang and `set -euo pipefail`.
Tests:
- Cause command failure and verify script exits non-zero.

R005  Statement: Require transaction and category identifiers from environment.
Design: Enforce `TXN_ID` and `CATEGORY_ID` via required parameter expansion.
Tests:
- Run without `TXN_ID` and verify immediate failure.
- Run without `CATEGORY_ID` and verify immediate failure.

R010  Statement: Support configurable API endpoint and database connection defaults.
Design: Use `TELLER_CLASSIFIER_API_URL` and `TELLER_DB_*` overrides with localhost defaults.
Tests:
- Override API URL and verify request targets override.

R015  Statement: Resolve DB password from environment or 1psa fallback.
Design: Use `TELLER_DB_PASSWORD` when set, otherwise read from 1psa item.
Tests:
- Unset DB password and verify fallback 1psa lookup is used.

R020  Statement: Post classification update request to classifier API.
Design: Send JSON payload to `/v1/transactions/classifications` with provided IDs.
Tests:
- Verify request body includes provided transaction and category identifiers.

R025  Statement: Query latest persisted classification for the target transaction.
Design: Execute `psql` query ordered by `updated_at DESC LIMIT 1`.
Tests:
- Verify output line is `<transaction_id>:<nys_snw_category_id>:<type>`.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `11_verify_reclassification_persistence.sh`.
