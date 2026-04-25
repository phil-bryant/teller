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

R020  Statement: Require globals dump file only for full restore mode.
Design: Validate selected `.dump` path always; require sibling `_globals.sql` only when `--table` is not provided.
Tests:
- Run full restore with missing globals file and verify restore is refused.
- Run table-scoped restore with missing globals file and verify restore still runs.

R025  Statement: Refuse full restore when target database already has teller schema unless table scope is provided.
Design: Query target database and abort only when schema `teller` exists and `--table` is not provided.
Tests:
- Restore into existing initialized db without `--table` and verify refusal message.
- Restore into existing initialized db with `--table` and verify restore is allowed.

R030  Statement: Restore globals only for full restore mode.
Design: For full restore, run globals SQL with `psql` then run `pg_restore --clean --if-exists --create`; for `--table` restore skip globals replay.
Tests:
- Verify full restore order is globals first, then database content.
- Verify table-scoped restore does not run globals replay.

R035  Statement: Support fail-fast SQL execution against the target database and print completion output.
Design: Provide a shared `psql -v ON_ERROR_STOP=1` helper bound to the target database for restore-related repair SQL, and emit final restore-complete message with selected dump file path.
Tests:
- Verify helper-invoked SQL exits non-zero on SQL errors.
- Verify successful run prints completion line with backup path.

R040  Statement: Accept optional table-scoped restore selection.
Design: Parse `--table <table_name|schema.table_name>` and restore only that table when provided.
Tests:
- Run with `--table teller.transaction` and verify only that table is restored.
- Run with `--table transaction` and verify teller schema-qualified restore target is used.

R045  Statement: Support combining explicit backup source with table-scoped restore.
Design: Allow `--from` and `--table` together so table-scoped restore can target any selected dump.
Tests:
- Run with both `--from <path.dump>` and `--table <table_name>` and verify selected dump plus table scope.

R050  Statement: Reapply deploy-time invariants after table-scoped restore for teller schema tables.
Design: After successful `pg_restore --table`, run scoped repair logic when the resolved table target is in schema `teller`.
Tests:
- Run `--table teller.<name>` and verify repair hook executes.
- Run `--table non_teller.<name>` and verify teller-specific repair hook is skipped.

R055  Statement: Ensure shared `updated_at` trigger function exists during scoped teller restore repair.
Design: Recreate `teller.update_updated_at()` idempotently before table-level trigger repair.
Tests:
- Drop `teller.update_updated_at()` before scoped restore and verify function exists after restore.

R060  Statement: Recreate per-table `updated_at` trigger only when restored teller table has `updated_at`.
Design: Detect `updated_at` column via `information_schema.columns`; when present, recreate `update_<table>_updated_at` trigger for restored table.
Tests:
- Restore a teller table with `updated_at` and verify trigger exists and is enabled.
- Restore a teller table without `updated_at` and verify no trigger create attempt is required.

R065  Statement: Reapply known table-specific DDL fixups after scoped restore where deploy defines post-creation adjustments.
Design: For `teller.transaction_nys_snw_category`, recreate the transaction FK with `ON DELETE CASCADE` to match deployment invariant.
Tests:
- Scoped restore `transaction_nys_snw_category` and verify FK delete action is `CASCADE`.

## Changelog

- 2026-04-21: Refined R020/R030 for table mode to skip globals requirements/replay and updated R040 table-name format.
- 2026-04-21: Refined R025 to allow restore into existing teller schema when `--table` is provided.
- 2026-04-21: Added R040 and R045 for optional `--table` restore scope and `--from` composition.
- 2026-04-24: Added R050/R055/R060/R065 for post-scoped-restore invariant repair; refined R035 for fail-fast target SQL helper coverage.
- 2026-04-19: Initial reverse-engineered requirements for `99_restore_database.sh`.
