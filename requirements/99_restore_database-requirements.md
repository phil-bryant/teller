# Restore Database Requirements

## Scope

Applies to `99_restore_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- R001-T01: Verify script exits on failing command and unset variable paths.

R005  Statement: Accept optional backup source path and support latest-backup defaulting.
Design: Parse `--from`; otherwise select newest `.dump` in local backups directory.
Tests:
- R005-T01: Run without args and verify newest dump is selected.
- R005-T02: Run with `--from` and verify provided path is selected.

R010  Statement: Require restore dependencies before restore operations.
Design: Validate `1psa`, `pg_restore`, and `psql` are available on PATH.
Tests:
- R010-T01: Remove `pg_restore` from PATH and verify clear failure.

R015  Statement: Resolve postgres password from configurable 1psa source.
Design: Read via `1psa -p` default or `1psa -f` override field, then validate non-empty.
Tests:
- R015-T01: Force empty password response and verify non-zero exit.

R020  Statement: Require globals dump file only for full restore mode.
Design: Validate selected `.dump` path always; require sibling `_globals.sql` only when `--table` is not provided.
Tests:
- R020-T01: Run full restore with missing globals file and verify restore is refused.
- R020-T02: Run table-scoped restore with missing globals file and verify restore still runs.

R025  Statement: Refuse full restore when target database already has teller schema unless table scope is provided.
Design: Query target database and abort only when schema `teller` exists and `--table` is not provided.
Tests:
- R025-T01: Restore into existing initialized db without `--table` and verify refusal message.
- R025-T02: Restore into existing initialized db with `--table` and verify restore is allowed.

R030  Statement: Restore globals only for full restore mode.
Design: For full restore, run globals SQL with `psql` then run `pg_restore --clean --if-exists --create`; for `--table` restore skip globals replay.
Tests:
- R030-T01: Verify full restore order is globals first, then database content.
- R030-T02: Verify table-scoped restore does not run globals replay.

R035  Statement: Support fail-fast SQL execution against the target database and print completion output.
Design: Provide a shared `psql -v ON_ERROR_STOP=1` helper bound to the target database for restore-related repair SQL, use parameterized `psql -v` binding for database-name lookups, and emit final restore-complete message with selected dump file path.
Tests:
- R035-T01: Verify helper-invoked SQL exits non-zero on SQL errors.
- R035-T02: Verify successful run prints completion line with backup path.

R040  Statement: Accept optional table-scoped restore selection.
Design: Parse `--table <table_name|schema.table_name>`, require both resolved schema and relation to be valid PostgreSQL identifiers, and restore only that table when provided.
Tests:
- R040-T01: Run with `--table teller.transaction` and verify only that table is restored.
- R040-T02: Run with `--table transaction` and verify teller schema-qualified restore target is used.

R045  Statement: Support combining explicit backup source with table-scoped restore.
Design: Allow `--from` and `--table` together so table-scoped restore can target any selected dump.
Tests:
- R045-T01: Run with both `--from <path.dump>` and `--table <table_name>` and verify selected dump plus table scope.

R050  Statement: Reapply deploy-time invariants after table-scoped restore for teller schema tables.
Design: After successful `pg_restore --table`, run scoped repair logic when the resolved table target is in schema `teller`.
Tests:
- R050-T01: Run `--table teller.<name>` and verify repair hook executes.
- R050-T02: Run `--table non_teller.<name>` and verify teller-specific repair hook is skipped.

R055  Statement: Ensure shared `updated_at` trigger function exists during scoped teller restore repair.
Design: Recreate `teller.update_updated_at()` idempotently before table-level trigger repair.
Tests:
- R055-T01: Drop `teller.update_updated_at()` before scoped restore and verify function exists after restore.

R060  Statement: Recreate per-table `updated_at` trigger only when restored teller table has `updated_at`.
Design: Detect `updated_at` column via `information_schema.columns`; when present, recreate `update_<table>_updated_at` trigger for restored table.
Tests:
- R060-T01: Restore a teller table with `updated_at` and verify trigger exists and is enabled.
- R060-T02: Restore a teller table without `updated_at` and verify no trigger create attempt is required.

R065  Statement: Reapply known table-specific DDL fixups after scoped restore where deploy defines post-creation adjustments.
Design: For `teller.transaction_nys_snw_category`, recreate the transaction FK with `ON DELETE CASCADE` to match deployment invariant.
Tests:
- R065-T01: Scoped restore `transaction_nys_snw_category` and verify FK delete action is `CASCADE`.

R100  Statement: Validate full-restore database target identifier before destructive restore checks.
Design: Require resolved `DATABASE_NAME` (env override or profile default) to be a valid PostgreSQL identifier before database existence checks or restore commands execute.
Tests:
- R100-T01: Provide invalid `DATABASE_NAME` and verify restore exits non-zero before SQL checks.

R101  Statement: Use parameterized SQL binding/formatting for scoped repair SQL that references dynamic table names.
Design: `information_schema` checks and trigger DDL in scoped repair logic must use `psql -v` variables and server-side identifier formatting instead of shell SQL interpolation.
Tests:
- R101-T01: Verify scoped repair query binds schema/table via `-v` variables and does not interpolate raw `TABLE_RELATION` into SQL.
- R101-T02: Provide malformed `--table` identifier and verify restore exits non-zero before repair SQL.

R102  Statement: Require and verify backup integrity manifest before full restore globals replay.
Design: In full restore mode, require sibling `*.manifest.sha256` for selected dump/globals pair and verify checksums before running globals SQL as postgres.
Tests:
- R102-T01: Run full restore with missing manifest and verify restore exits non-zero.
- R102-T02: Run full restore with checksum verification failure and verify restore exits non-zero before globals replay.

R070  Statement: Resolve teller password from configurable 1psa source for full-restore credential re-sync.
Design: Read teller password via `TELLER_PSA_ITEM`/`TELLER_PSA_FIELD` with default item `localhost_postgres_teller`, and require non-empty value before restore proceeds.
Tests:
- R070-T01: Force empty teller password lookup and verify restore exits non-zero with clear error.

R075  Statement: Re-sync teller role credential to current 1psa secret after full restore.
Design: In full restore mode, after globals replay and database restore, run `ALTER USER teller WITH PASSWORD ...` using resolved teller secret.
Tests:
- R075-T01: Run full restore from globals containing stale teller hash and verify post-restore role password is updated to current secret source.

R080  Statement: Verify teller authentication succeeds after full restore credential re-sync.
Design: After full restore and password reset, perform `psql` login as `teller` against target database and fail restore if authentication does not succeed.
Tests:
- R080-T01: Force mismatch between restored role password and expected secret and verify script fails on post-restore teller login check.

R085  Statement: Resolve the active DB profile via the shared `src/scripts/db_profile_export.sh` helper and refuse to restore when the helper is missing.
Design: Source whitelisted `PROFILE_NAME`/`PROFILE_TARGET`/`PG_*` exports from the helper before any restore actions, and require non-empty `PROFILE_NAME`/`PROFILE_TARGET`/`PG_DBNAME` so restore never targets a stale hard-coded database.
Tests:
- R085-T01: Verify successful run resolves profile via helper and continues with the resolved target (local-target full restore path exercises this).

R090  Statement: Managed-target restore refuses full restore (cannot CREATE DATABASE or replay globals) and only supports `--table` scoped restore against the direct (non-pooler) host using the profile's connection user.
Design: When `PROFILE_TARGET=managed` and no `--table` is provided, exit non-zero with explicit guidance to re-run with `--table schema.table_name`; otherwise re-resolve via the `supabase_direct` profile, read the password from `PG_ONEPSA_ITEM` via `1psa` (with `TELLER_DB_PASSWORD` env override), and invoke `pg_restore -h <PG_HOST> -p <PG_PORT> -U <PG_USER> -d <PG_DBNAME> --clean --if-exists --schema <schema> --table <table>`.
Tests:
- R090-T01: Verify managed-target run without `--table` exits non-zero with the explicit refuse message and guidance.
- R090-T02: Verify managed-target `--table` restore invokes `pg_restore` against the resolved managed host/user/database.
- R090-T03: Verify managed-target `--table` restore passes the resolved schema/table to `pg_restore` and prints the completion line.

R095  Statement: Honor existing `DATABASE_NAME` env override for backward compatibility on local-target runs while defaulting to the profile-resolved `PG_DBNAME`.
Design: For local-target runs, set `DATABASE_NAME="${DATABASE_NAME:-$PG_DBNAME}"` so callers that previously pinned `DATABASE_NAME=prod` keep working, while operators on alternative local DBs pick up the resolved profile DB by default.
Tests:
- R095-T01: Verify local-target run defaults `DATABASE_NAME` from the profile-resolved `PG_DBNAME` when no env override is set (exercised by the existing latest-dump completion test).

## Changelog

- 2026-05-30: Added R100-R102 for identifier validation, scoped repair SQL parameterization, and full-restore manifest integrity verification.
- 2026-05-26: Added R085/R090/R095 for profile-aware restore behavior; managed-target restore is `--table`-only with profile-resolved credentials.
- 2026-04-21: Refined R020/R030 for table mode to skip globals requirements/replay and updated R040 table-name format.
- 2026-04-21: Refined R025 to allow restore into existing teller schema when `--table` is provided.
- 2026-04-21: Added R040 and R045 for optional `--table` restore scope and `--from` composition.
- 2026-04-24: Added R050/R055/R060/R065 for post-scoped-restore invariant repair; refined R035 for fail-fast target SQL helper coverage.
- 2026-05-09: Added R070/R075/R080 for full-restore teller credential re-sync and auth verification against current 1psa secret.
- 2026-04-19: Initial reverse-engineered requirements for `99_restore_database.sh`.
