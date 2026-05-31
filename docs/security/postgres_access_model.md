# Postgres Access Model (Single-Tenant)

This service-role model keeps the database single-tenant and enforces boundaries through roles, grants, and row-level security.

## Runtime Role Matrix

| Role | Intended Service Path | Baseline Capability |
| --- | --- | --- |
| `teller_api_reader` | Read-only API requests | `SELECT` via `teller_read` grants. |
| `teller_api_writer` | Classification API mutation paths | Read/write DML via `teller_write` grants. |
| `teller_ingest_writer` | Teller ingest and reconcile scripts | Read/write/delete for ingestion + reconcile flows. |
| `teller_migration_admin` | Controlled schema migrations | Administrative schema changes via `teller_admin`. |

## RLS Model (Single-Tenant)

- No tenant IDs are introduced solely for RLS.
- RLS is enabled on high-risk financial/PII tables.
- Policies are role-aware and fail closed for unrecognized roles.
- `FORCE ROW LEVEL SECURITY` is enabled on protected tables to avoid accidental owner bypass.

## Session Context Keys

Application services should set session context keys per request/operation:

- `teller.request_id`: correlation ID.
- `teller.actor_id`: authenticated caller identifier.
- `teller.actor_service`: service/component name.

These keys are captured in audit rows for forensic reconstruction.

## Access Pattern

- Application code reads masked views for PII display paths.
- Raw base-table access is restricted to narrowly scoped service roles.
- Security verification checks enforce RLS, role existence, and secure-view presence.
