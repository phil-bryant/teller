# Teller DB Requirements

## Scope

Applies to `src/teller/teller_db.py`.

R025  Statement: Resolve the DB password through env or libonepsa fallback.
Design: `TELLER_DB_PASSWORD` wins; otherwise `_read_password` reads from libonepsa using the resolved profile's `onepsa_item`. Empty results raise `RuntimeError`.
Tests:
- R025-T01: With `TELLER_DB_PASSWORD` set, verify the env value is returned and libonepsa is not invoked.
- R025-T02: With `TELLER_DB_PASSWORD` unset and a profile lacking `1psa_item`, verify a `RuntimeError` is raised.

R030  Statement: Build one cached SQLAlchemy engine per process.
Design: `get_engine()` lazily creates a SQLAlchemy engine from the resolved profile, using PostgreSQL settings for postgres/supabase targets and SQLite settings for sqlite target, caching it in module state.
Tests:
- R030-T01: Patch `create_engine` and verify two `get_engine()` calls produce one engine and one underlying call.
- R030-T02: Resolve SQLite profile and verify `get_engine()` builds sqlite engine without password lookup.

R035  Statement: Apply profile sslmode to the connection.
Design: For PostgreSQL-family targets, when profile sslmode is non-empty and not `disable`, include it in `connect_args` so Supabase TLS is enforced; SQLite targets skip sslmode handling.
Tests:
- R035-T01: Resolve a profile with `sslmode = "require"` and verify `create_engine` receives `sslmode=require` in `connect_args`.
- R035-T02: Resolve a profile with `sslmode = "disable"` and verify `connect_args` contains no `sslmode` key.

R040  Statement: Configure session search_path and optional runtime role on connect.
Design: PostgreSQL-family connect listener runs `SET search_path TO <search_path>` and optional `SET ROLE`; SQLite connect listener performs SQLite-specific attach/pragma setup and skips PostgreSQL session statements.
Rationale: Local PostgreSQL uses the `teller_write` role; Supabase managed Postgres lets `runtime_role` stay empty so `SET ROLE` is skipped.
Tests:
- R040-T01: Drive the connect listener with `runtime_role = "teller_write"` and verify both `SET search_path` and `SET ROLE` execute against the cursor.
- R040-T02: Drive the connect listener with empty `runtime_role` and verify `SET ROLE` is not executed.

## Changelog

- 2026-05-30: Extended engine requirements to include SQLite target behavior.
- 2026-05-21: Initial requirements for `teller_db` profile-aware engine factory.
