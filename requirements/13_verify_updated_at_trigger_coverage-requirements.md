# Verify Updated At Trigger Coverage Requirements

## Scope

Applies to `13_verify_updated_at_trigger_coverage.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `zsh` shebang and `set -euo pipefail`.
Tests:
- Cause command failure and verify script exits non-zero.

R005  Statement: Support configurable database connection defaults.
Design: Read `TELLER_DB_HOST`, `TELLER_DB_PORT`, `TELLER_DB_NAME`, and `TELLER_DB_USER` with localhost defaults.
Tests:
- Override DB host/user env vars and verify `psql` receives the overrides.

R010  Statement: Resolve DB password from environment or 1psa fallback.
Design: Use `TELLER_DB_PASSWORD` when set, otherwise resolve from `TELLER_PSA_ITEM`.
Tests:
- Unset `TELLER_DB_PASSWORD` and verify fallback credential lookup path is used.

R015  Statement: Refuse verification when DB password resolves empty.
Design: Validate resolved password before executing SQL checks and print `❌ FAIL:` with a clear reason before exiting non-zero.
Tests:
- Force empty password and verify output starts with `❌ FAIL:` and script exits non-zero.

R020  Statement: Detect tables missing updated_at trigger coverage.
Design: Compare tables with `updated_at` columns against enabled `teller.update_updated_at` trigger attachments via catalog query.
Tests:
- Remove one trigger in a test DB and verify the table appears in failure output.

R025  Statement: Exit non-zero when coverage gaps are detected.
Design: Treat any missing table rows from verification query as failure, print a `❌ FAIL:` header, and list missing table names.
Tests:
- Verify output starts with `❌ FAIL:` and exit code is non-zero when SQL query returns at least one table.

R030  Statement: Print explicit success when coverage is complete.
Design: Print a single `✅ PASS:` message when no missing tables are returned.
Tests:
- Verify output starts with `✅ PASS:` after full trigger coverage is present.

## Changelog

- 2026-04-22: Require `✅ PASS:` and `❌ FAIL:` output prefixes for verification outcomes.
- 2026-04-21: Initial requirements for `13_verify_updated_at_trigger_coverage.sh`.
