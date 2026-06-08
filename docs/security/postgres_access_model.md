# Postgres Access Model (Single-Tenant, Multi-Schema)

This service-role model keeps the database single-tenant and enforces boundaries through roles, grants, and row-level security across `teller`, `classy`, and `matchy` schemas.

## Runtime Role Matrix

| Role | Intended Service Path | Baseline Capability |
| --- | --- | --- |
| `teller_api_reader` | Read-only API requests | `SELECT` via `teller_read` grants. |
| `teller_api_writer` | Classification API mutation paths | Read/write DML via `teller_write` grants. |
| `teller_ingest_writer` | Teller ingest and reconcile scripts | Read/write/delete for ingestion + reconcile flows. |
| `teller_migration_admin` | Controlled schema migrations | Administrative schema changes via `teller_admin`. |
| `classy_api_reader` | Classy read paths | `SELECT` on `classy.*` and allowed cross-schema reads. |
| `classy_api_writer` | Classy classification/category writes | Read/write on `classy.*`, explicit FK/read access to `teller.transaction`. |
| `classy_migration_admin` | Classy schema migrations | Administrative schema changes via `classy_admin`. |
| `matchy_service_reader` | Matchy read/reporting paths | `SELECT` on `matchy.*` and allowed cross-schema reads. |
| `matchy_service_writer` | Matchy run/candidate/match writes | Read/write on `matchy.*`, explicit FK/read access to `teller.transaction`. |
| `matchy_migration_admin` | Matchy schema migrations | Administrative schema changes via `matchy_admin`. |

## RLS Model (Single-Tenant)

- No tenant IDs are introduced solely for RLS.
- RLS is enabled on high-risk financial/PII tables and product-state tables in `classy`/`matchy` where cross-service access occurs.
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
- Raw base-table access is restricted to narrowly scoped service roles within each owning schema.
- Cross-schema access is explicit (`teller.transaction` remains system-of-record; Classy/Matchy product state is owned outside `teller`).
- Security verification checks enforce RLS, role existence, and secure-view presence.
