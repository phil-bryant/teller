# Create Audit Requirements

## Scope

Applies to `src/sql/postgres/create_audit.sql`.

## Ownership Boundaries

Deployment sequencing and invocation remain defined in `requirements/07_deploy_database-requirements.md`, and ORM/table naming contracts remain defined in `requirements/teller_object-requirements.md`.

R001  Statement: Persist row-level audit events in a dedicated log table.
Design: Create `teller.audit_log` with action metadata, record identifier, actor, timestamp, and JSON payload columns for old/new row data.
Tests:
- R001-T01: Execute DDL and verify `teller.audit_log` exists with expected columns and action constraint.

R005  Statement: Resolve primary-key column names for teller tables.
Design: Provide `teller.get_primary_key_columns(...)` that queries `information_schema` constraints and returns ordered PK column names.
Tests:
- R005-T01: Call the function for a single-key table and a composite-key table and verify returned ordered column arrays.

R010  Statement: Emit operation-specific audit rows for INSERT, UPDATE, and DELETE.
Design: Implement `teller.audit_trigger_func()` to insert into `teller.audit_log` with `old_data`/`new_data` populated according to `TG_OP`.
Tests:
- R010-T01: Perform insert, update, and delete against a trigger-managed table and verify one audit row per operation with correct payload shape.

R015  Statement: Normalize audited `record_id` values for both single and composite primary keys.
Design: In `teller.audit_trigger_func()`, read key values from `COALESCE(NEW, OLD)` and serialize single keys directly and composite keys as a brace-delimited list.
Tests:
- R015-T01: Audit events on a composite-key table and verify `record_id` stores all key parts.

R020  Statement: Attach audit triggers to every teller base table except the audit table itself.
Design: Iterate teller base tables from `information_schema` and create `AFTER INSERT OR UPDATE OR DELETE` triggers that execute `teller.audit_trigger_func()`.
Tests:
- R020-T01: Verify trigger creation excludes `audit_log` and includes other teller base tables.

## Changelog

- 2026-04-23: Added dedicated SQL requirements for `create_audit.sql`.
