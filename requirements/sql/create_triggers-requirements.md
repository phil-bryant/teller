# Create Triggers Requirements

## Scope

Applies to `sql/postgres/create_triggers.sql`.

## Ownership Boundaries

Deployment sequencing and invocation remain defined in `requirements/07_deploy_database-requirements.md`, and ORM/table naming contracts remain defined in `requirements/teller_object-requirements.md`.

R001  Statement: Provide a shared trigger function that refreshes `updated_at` on row updates.
Design: Define `teller.update_updated_at()` as a `plpgsql` trigger function that assigns `CURRENT_TIMESTAMP` to `NEW.updated_at`.
Tests:
- R001-T01: Update a row in a trigger-managed table and verify `updated_at` is changed by the trigger.

R005  Statement: Attach `updated_at` triggers to all eligible teller base tables.
Design: Iterate `information_schema` tables in schema `teller` and target only base tables containing an `updated_at` column.
Tests:
- R005-T01: Add a teller table with `updated_at`, run script, and verify trigger creation for that table.

R010  Statement: Discover trigger targets from system metadata in deterministic order.
Design: Select table names from `information_schema.tables` joined to `information_schema.columns`, sorted by table name.
Tests:
- R010-T01: Re-run script and verify target table traversal order remains stable.

R015  Statement: Replace existing user-defined updated-at triggers during redeploy.
Design: Detect an existing non-internal trigger per target table and drop it before creating the current definition.
Tests:
- R015-T01: Execute script twice and verify no duplicate trigger error occurs on the second run.

R020  Statement: Create per-table `BEFORE UPDATE` triggers that call `teller.update_updated_at()`.
Design: Build trigger names as `update_<table_name>_updated_at` and execute dynamic SQL to create each trigger on `teller.<table_name>`.
Tests:
- R020-T01: Inspect `pg_trigger` metadata and verify each eligible table has the expected trigger name and function binding.

## Changelog

- 2026-04-23: Added dedicated SQL requirements for `create_triggers.sql`.
