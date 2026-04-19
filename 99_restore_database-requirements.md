# Restore Database Requirements

## Scope

Applies to `99_restore_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- Verify script exits on failing command and unset variable paths.

R005  Statement: Accept optional backup source path and support latest-backup defaulting.
Design: Parse `--from`; otherwise select newest `.dump` in local backups directory.
Tests:
- Run without args and verify newest dump is selected.
- Run with `--from` and verify provided path is selected.

R010  Statement: Require restore dependencies before restore operations.
Design: Validate `1psa`, `pg_restore`, and `psql` are available on PATH.
Tests:
- Remove `pg_restore` from PATH and verify clear failure.

R015  Statement: Resolve postgres password from configurable 1psa source.
Design: Read via `1psa -p` default or `1psa -f` override field, then validate non-empty.
Tests:
- Force empty password response and verify non-zero exit.

R020  Statement: Require both database dump and matching globals dump files.
Design: Validate selected `.dump` path and sibling `_globals.sql` file.
Tests:
- Delete matching globals file and verify restore is refused.

R025  Statement: Refuse restore when target database already has teller schema.
Design: Query target database and abort if schema `teller` exists.
Tests:
- Restore into existing initialized db and verify refusal message.

R030  Statement: Restore globals before database content restore.
Design: Run globals SQL with `psql` then run `pg_restore --clean --if-exists --create`.
Tests:
- Verify restore order is globals first, then database content.

R035  Statement: Print completion output with source backup path.
Design: Emit final restore-complete message with selected dump file path.
Tests:
- Verify successful run prints completion line with backup path.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `99_restore_database.sh`.
