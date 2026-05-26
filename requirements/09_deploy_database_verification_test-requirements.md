# Verify Deploy Database Requirements

## Scope

Applies to `tests/t05_deploy_database_verification_test.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `zsh` shebang and `set -euo pipefail`.
Tests:
- R001-T01: Cause a command failure and verify script exits non-zero.

R005  Statement: Support configurable database connection defaults.
Design: Read `TELLER_DB_HOST`, `TELLER_DB_PORT`, `TELLER_DB_NAME`, and `TELLER_DB_USER` with localhost defaults.
Tests:
- R005-T01: Override DB host/user env vars and verify `psql` receives the overrides.

R010  Statement: Resolve DB password from environment or 1psa fallback.
Design: Use `TELLER_DB_PASSWORD` when set, otherwise resolve from `TELLER_PSA_ITEM`.
Tests:
- R010-T01: Unset `TELLER_DB_PASSWORD` and verify fallback credential lookup path is used.

R015  Statement: Refuse verification when DB password resolves empty.
Design: Validate resolved password before running checks, print `❌ FAIL:` with a clear reason, and exit non-zero.
Tests:
- R015-T01: Force empty password and verify output starts with `❌ FAIL:` and script exits non-zero.

R020  Statement: Verify required deployed database objects exist.
Design: Check for required roles/schema/core relations deployed by `05_deploy_database.sh` and report missing objects.
Tests:
- R020-T01: Drop or rename one required object in a test DB and verify it appears in failure output.

R025  Statement: Verify transaction classification FK cascades deletes.
Design: Assert `teller.transaction_nys_snw_category(transaction_id)` references `teller.transaction(transaction_id)` with `ON DELETE CASCADE`.
Tests:
- R025-T01: Alter FK without cascade and verify script fails with explicit FK diagnostic.

R030  Statement: Verify updated_at trigger wiring after deploy.
Design: Assert `teller.update_updated_at` exists and that `teller.transaction_nys_snw_category` has a non-internal trigger calling it.
Tests:
- R030-T01: Drop function or trigger and verify script fails with explicit trigger diagnostic.

R040  Statement: Detect tables missing updated_at trigger coverage.
Design: Compare all `teller` base tables that include `updated_at` against enabled non-internal triggers using `teller.update_updated_at`.
Tests:
- R040-T01: Remove one trigger in a test DB and verify the table appears in failure output.

R045  Statement: Exit non-zero when updated_at trigger coverage gaps are detected.
Design: Treat any missing table rows from the coverage query as failure and print each table with a clear `missing updated_at trigger coverage:` diagnostic.
Tests:
- R045-T01: Verify output includes each missing table and exits non-zero when query returns uncovered tables.

R035  Statement: Print explicit pass/fail verification result.
Design: Print one `✅ PASS:` line only when all checks pass (including updated_at coverage); otherwise print `❌ FAIL:` header, list each failed check, and exit non-zero.
Tests:
- R035-T01: Verify successful run emits exactly one `✅ PASS:` line.

R050  Statement: Skip teller-role existence checks on managed Postgres targets.
Design: Resolve the active DB profile via `src/scripts/db_profile_export.sh`; when `PROFILE_TARGET=managed`, omit the `teller_read/teller_write/teller_admin/teller` role check that does not apply on Supabase.
Tests:
- R050-T01: Run verification with `TELLER_DB_PROFILE=supabase` and verify the role check SQL is not executed.

R055  Statement: Resolve verification DB password using the active profile's 1psa item.
Design: When `TELLER_DB_PASSWORD` is unset, fall back to `1psa -p <profile.onepsa_item>`; allow `TELLER_PSA_ITEM` to override.
Tests:
- R055-T01: Run with managed profile and verify the profile's `1psa_item` is queried via 1psa.

R060  Statement: Confirm live TLS when the resolved profile requires SSL.
Design: When `PG_SSLMODE` is `require`, `verify-ca`, or `verify-full`, query `pg_stat_ssl` for the current backend; record a failure if `ssl` is not `t`.
Rationale: A misconfigured client could still negotiate plaintext if the server tolerates either. Verifying `pg_stat_ssl` proves the live session is actually encrypted.
Tests:
- R060-T01: Stub psql to return `f` for the `pg_stat_ssl` probe with `PG_SSLMODE=require` and verify the script fails with an SSL diagnostic.
- R060-T02: With `PG_SSLMODE=disable`, verify the SSL probe is skipped entirely.

R065  Statement: Refuse verification when DB profile setup is missing.
Design: If profile resolution fails (no `config/db-profiles.json`/candidate profile document), exit non-zero and print setup guidance to copy `config/db-profiles-EXAMPLE.json` instead of verifying with implicit local defaults.
Tests:
- R065-T01: Run with no candidate profile file and verify verification exits non-zero with copy-guidance text.

## Changelog

- 2026-05-23: Added R065 to require explicit DB profile setup before verification.
- 2026-05-22: Added R060 to confirm live TLS when the resolved profile requires SSL.
- 2026-05-21: Added R050 and R055 for profile-aware verification on managed Postgres targets.
- 2026-05-14: Combined updated_at coverage verification into `09_deploy_database_verification_test.sh` (absorbed former `09` lane behavior).
- 2026-04-22: Initial requirements for `09_deploy_database_verification_test.sh`.
