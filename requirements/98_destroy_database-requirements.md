# Destroy Database Requirements

## Scope

Applies to `98_destroy_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- R001-T01: Force a failing SQL command and verify non-zero exit.

R005  Statement: Require `1psa` and resolve postgres password from configured source.
Design: Check `1psa`, then read password via default or override field.
Tests:
- R005-T01: Run without `1psa` and verify clear failure message.

R010  Statement: Require explicit destructive confirmation.
Design: Prompt user to type `destroy` before any database teardown.
Tests:
- R010-T01: Provide wrong confirmation and verify teardown does not run.

R015  Statement: Clean dependent resources before dropping prod database.
Design: If prod exists, drop dependent view and terminate active prod sessions.
Tests:
- R015-T01: With live sessions, verify terminate query executes before database drop.

R020  Statement: Drop target database and teller roles idempotently.
Design: Execute `DROP ... IF EXISTS` for database, user, and teller roles.
Tests:
- R020-T01: Run script twice and verify second run remains safe.

R025  Statement: Print completion status after teardown steps finish.
Design: Emit final cleanup completion line.
Tests:
- R025-T01: Verify successful run prints completion message.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `98_destroy_database.sh`.
