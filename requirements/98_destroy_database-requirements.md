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

R026  Statement: Support SQLite teardown through the existing destroy entrypoint.
Design: When `PROFILE_TARGET=sqlite`, require the same explicit confirmation and destroy the resolved SQLite database artifact safely.
Tests:
- R026-T01: Run with sqlite profile and verify confirmed destroy removes the SQLite artifact and prints completion output.

R030  Statement: Validate local database identifier before destructive local teardown SQL.
Design: Require `LOCAL_DBNAME` (resolved from profile `PG_DBNAME`) to be a valid PostgreSQL identifier before existence checks, session termination, and drop statements.
Tests:
- R030-T01: Provide invalid `PG_DBNAME` and verify local destroy exits non-zero before SQL teardown.

R031  Statement: Use parameterized SQL for local database-name queries and DROP statements.
Design: Local destroy SQL touching database names (`pg_database` checks, backend termination filters, and `DROP DATABASE`) must use `psql -v` variable binding and server-side quoting/formatting instead of shell interpolation.
Tests:
- R031-T01: Verify local destroy uses `-v db_name=...` for DB existence and terminate queries.
- R031-T02: Verify local `DROP DATABASE` uses server-side formatted identifier execution (`format(... ) \\gexec`).

R032  Statement: Validate managed schema identifier before destructive managed schema teardown.
Design: Require managed `SCHEMA_NAME` (from `PG_SEARCH_PATH`) to be a single valid PostgreSQL identifier and continue refusing protected schemas (`public`, `pg_catalog`, `information_schema`).
Tests:
- R032-T01: Provide invalid managed schema identifier and verify destroy exits non-zero before DROP.

R033  Statement: Use parameterized server-side identifier formatting for managed `DROP SCHEMA`.
Design: Managed schema drop must pass schema via `psql -v schema_name=...` and execute `DROP SCHEMA` using server-side identifier formatting (`format('%I', ...)` + `\\gexec`) rather than shell interpolation.
Tests:
- R033-T01: Verify managed destroy invokes parameterized `DROP SCHEMA` via formatted `\\gexec` SQL.

## Changelog

- 2026-05-30: Added R026 for SQLite teardown behavior through existing script.
- 2026-05-30: Added R030-R033 for identifier validation and parameterized local/managed destroy SQL execution.
- 2026-04-19: Initial reverse-engineered requirements for `98_destroy_database.sh`.
