# Backup Database Requirements

## Scope

Applies to `97_backup_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- R001-T01: Verify script exits on unset variable and failing command paths.

R005  Statement: Require backup dependencies before backup operations.
Design: Validate `1psa`, `pg_dump`, and `pg_dumpall` commands on PATH.
Tests:
- R005-T01: Remove `pg_dump` from PATH and verify clear failure message.

R010  Statement: Resolve postgres password from configurable 1psa item and field.
Design: Read password using `1psa -p` default or `1psa -f` override field.
Tests:
- R010-T01: Override field and verify lookup path succeeds.

R015  Statement: Refuse backup when postgres password resolves empty.
Design: Validate non-empty password before dump commands.
Tests:
- R015-T01: Force empty 1psa result and verify script exits non-zero.

R020  Statement: Create backup output directory with restricted permissions.
Design: Ensure `backups/` exists and mode is `770`.
Tests:
- R020-T01: Remove directory and verify recreation with expected permissions.

R025  Statement: Write database dump in custom format with create-database metadata.
Design: Run `pg_dump -Fc -C` into timestamped `.dump` file.
Tests:
- R025-T01: Verify output `.dump` file exists with timestamped naming.

R030  Statement: Write globals-only dump for roles and grants.
Design: Run `pg_dumpall --globals-only` into matching `_globals.sql` file.
Tests:
- R030-T01: Verify globals file exists beside database dump.

R035  Statement: Restrict backup file permissions and print output paths.
Design: Apply mode `660` to both output files and print their locations.
Tests:
- R035-T01: Verify file modes and output lines after successful run.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `97_backup_database.sh`.
