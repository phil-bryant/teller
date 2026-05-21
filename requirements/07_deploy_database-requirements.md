# Deploy Database Requirements

## Scope

Applies to `07_deploy_database.sh`.

R001  Statement: Fail fast when deployment steps fail.
Design: Use `set -e` and exit non-zero on unrecoverable errors.
Tests:
- R001-T01: Force failing SQL execution and verify script exits non-zero.

R005  Statement: Require `1psa` before credential lookup.
Design: Check `1psa` on PATH before password retrieval.
Tests:
- R005-T01: Run without `1psa` and verify clear failure message.

R006  Statement: Ensure `psql` exits immediately when SQL execution hits an error.
Design: Define shared `psql` options with `-v ON_ERROR_STOP=1` and apply them on every SQL invocation path.
Tests:
- R006-T01: Introduce a SQL syntax error during deploy and verify execution stops at the failing statement.

R007  Statement: Execute postgres-admin SQL through a reusable fail-fast wrapper.
Design: Provide a dedicated postgres helper that injects admin credentials plus shared fail-fast options.
Tests:
- R007-T01: Run bootstrap SQL through helper and verify command includes fail-fast behavior and postgres role.

R008  Statement: Execute teller-user SQL through a reusable fail-fast wrapper.
Design: Provide a dedicated teller helper that injects teller credentials, target database, and shared fail-fast options.
Tests:
- R008-T01: Run schema SQL through helper and verify command includes fail-fast behavior, teller role, and `prod` database target.

R010  Statement: Resolve postgres admin password from configurable 1psa source.
Design: Use default item/field with override support via environment variables.
Tests:
- R010-T01: Override item/field and verify resolved password path is used.

R015  Statement: Resolve teller database password from configurable 1psa source.
Design: Use default teller item/field with override support via environment variables.
Tests:
- R015-T01: Override teller item/field and verify resolved password path is used.

R020  Statement: Refuse deploy when required passwords resolve empty.
Design: Validate both password variables before SQL steps.
Tests:
- R020-T01: Return empty password from 1psa and verify script exits non-zero.

R025  Statement: Run admin bootstrap SQL as postgres user.
Design: Execute `create_database.sql` then `configure_database.sql` with postgres credentials.
Tests:
- R025-T01: Verify bootstrap SQL scripts execute in expected order.

R030  Statement: Build teller schema objects in declared dependency order.
Design: Execute teller SQL files sequentially as teller user against `prod`.
Tests:
- R030-T01: Verify later table creation depends on earlier files and run succeeds in listed order.

R035  Statement: Resolve SQL file directory relative to script location.
Design: Use `sql/postgres` under script directory.
Tests:
- R035-T01: Run script from a different working directory and verify SQL files still resolve.

R040  Statement: Attach updated_at triggers after all table DDL creation.
Design: Execute `create_triggers.sql` only after all `teller_*.sql` table files that define `updated_at` are applied.
Tests:
- R040-T01: Verify deploy order runs `create_triggers.sql` after `teller_transaction_nys_snw_category.sql`.

R045  Statement: Ensure transaction classifications cascade-delete with parent transaction removal.
Design: Enforce `ON DELETE CASCADE` on `teller.transaction_nys_snw_category(transaction_id)` during deploy, including existing databases.
Tests:
- R045-T01: Delete a row from `teller.transaction` with a linked `transaction_nys_snw_category` row and verify child row is removed automatically.
- R045-T02: Re-run deploy and verify FK remains present with cascade behavior.

R050  Statement: Ensure pgTAP extension is installed in `prod` during deploy.
Design: Run `CREATE EXTENSION IF NOT EXISTS pgtap;` as postgres against `prod` after database configuration.
Tests:
- R050-T01: Verify deploy invokes SQL that creates `pgtap` extension in `prod`.

R055  Statement: Apply ingest-role grants required for reconcile and audit workflows.
Design: Execute `grant_ingest_reconcile_privileges.sql` during deploy after schema objects and audit/view/trigger assets are in place.
Tests:
- R055-T01: Verify deploy invokes `grant_ingest_reconcile_privileges.sql` against `prod` as teller role.

R060  Statement: Resolve the active DB profile and target before deploy.
Design: Source `scripts/db_profile_export.sh` to populate `PROFILE_TARGET`, `PG_HOST`, `PG_PORT`, `PG_DBNAME`, `PG_USER`, `PG_SSLMODE`, and `PG_ONEPSA_ITEM`; re-resolve as `supabase_direct` for managed deploys so DDL bypasses the transaction pooler.
Tests:
- R060-T01: Set `TELLER_DB_PROFILE=supabase` and verify managed-deploy path is taken with the direct host.

R065  Statement: Skip database/role bootstrap on managed targets.
Design: When `PROFILE_TARGET` is `managed`, skip `create_database.sql`, `configure_database.sql`, and the postgres-admin password resolution.
Tests:
- R065-T01: Run with managed profile and verify neither bootstrap SQL file is invoked.

R070  Statement: Apply schema files using the profile connection user on managed targets.
Design: For managed targets, run every `teller_*.sql`, the FK cascade ALTER, `create_triggers.sql`, the transaction info view, and `create_audit.sql` as the profile-supplied user (e.g. `postgres`) against the profile's database.
Tests:
- R070-T01: Run with managed profile and verify the same teller schema files are applied as on local.

R075  Statement: Skip pgtap extension creation on managed targets.
Design: Managed-deploy path omits `CREATE EXTENSION IF NOT EXISTS pgtap` because Supabase does not allow-list `pgtap`.
Tests:
- R075-T01: Run with managed profile and verify no `CREATE EXTENSION` invocation occurs.

R080  Statement: Skip ingest-reconcile grants on managed targets.
Design: Managed-deploy path skips `grant_ingest_reconcile_privileges.sql` because no `teller_write` role exists on managed Postgres.
Tests:
- R080-T01: Run with managed profile and verify the grant SQL file is not invoked.

R085  Statement: Allow idempotent re-runs against an existing local database.
Design: Skip `create_database.sql` when `prod` already exists; rely on idempotent SQL files (`IF NOT EXISTS`, `CREATE OR REPLACE`, guarded `DO` blocks) for every other DDL step.
Tests:
- R085-T01: Run deploy twice in succession against a stub psql and verify both runs exit zero.

## Changelog

- 2026-05-21: Added R060-R085 for profile-aware deploy that supports managed PostgreSQL targets and idempotent re-runs.
- 2026-05-13: Added R055 for ingest reconcile/audit grant application during deploy.
- 2026-04-24: Added R006-R008 for fail-fast `psql` options and wrapper function coverage.
- 2026-04-26: Added R050 to create `pgtap` extension in `prod` during deploy bootstrap.
- 2026-04-21: Added R040 trigger-order requirement to ensure full updated_at coverage.
- 2026-04-22: Added R045 to enforce cascading delete behavior for transaction classifications.
- 2026-04-19: Initial reverse-engineered requirements for `07_deploy_database.sh`.
