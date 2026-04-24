# Verify Deploy Database Requirements

## Scope

Applies to `07_verify_deploy_database.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `zsh` shebang and `set -euo pipefail`.
Tests:
- Cause a command failure and verify script exits non-zero.

R005  Statement: Support configurable database connection defaults.
Design: Read `TELLER_DB_HOST`, `TELLER_DB_PORT`, `TELLER_DB_NAME`, and `TELLER_DB_USER` with localhost defaults.
Tests:
- Override DB host/user env vars and verify `psql` receives the overrides.

R010  Statement: Resolve DB password from environment or 1psa fallback.
Design: Use `TELLER_DB_PASSWORD` when set, otherwise resolve from `TELLER_PSA_ITEM`.
Tests:
- Unset `TELLER_DB_PASSWORD` and verify fallback credential lookup path is used.

R015  Statement: Refuse verification when DB password resolves empty.
Design: Validate resolved password before running checks, print `❌ FAIL:` with a clear reason, and exit non-zero.
Tests:
- Force empty password and verify output starts with `❌ FAIL:` and script exits non-zero.

R020  Statement: Verify required deployed database objects exist.
Design: Check for required roles/schema/core relations deployed by `06_deploy_database.sh` and report missing objects.
Tests:
- Drop or rename one required object in a test DB and verify it appears in failure output.

R025  Statement: Verify transaction classification FK cascades deletes.
Design: Assert `teller.transaction_nys_snw_category(transaction_id)` references `teller.transaction(transaction_id)` with `ON DELETE CASCADE`.
Tests:
- Alter FK without cascade and verify script fails with explicit FK diagnostic.

R030  Statement: Verify updated_at trigger wiring after deploy.
Design: Assert `teller.update_updated_at` exists and that `teller.transaction_nys_snw_category` has a non-internal trigger calling it.
Tests:
- Drop function or trigger and verify script fails with explicit trigger diagnostic.

R035  Statement: Print explicit pass/fail verification result.
Design: Print one `✅ PASS:` line only when all checks pass; otherwise print `❌ FAIL:` header, list each failed check, and exit non-zero.
Tests:
- Verify all-pass run emits a single `✅ PASS:` line.
- Verify any failed check emits `❌ FAIL:` details and exits non-zero.

## Changelog

- 2026-04-22: Initial requirements for `07_verify_deploy_database.sh`.
