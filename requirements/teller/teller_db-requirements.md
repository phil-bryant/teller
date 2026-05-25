# Teller DB Requirements

## Scope

Applies to `src/teller/teller_db.py`.

R025  Statement: Resolve the DB password through env or libonepsa fallback.
Design: `TELLER_DB_PASSWORD` wins; otherwise `_read_password` reads from libonepsa using the resolved profile's `onepsa_item`. Empty results raise `RuntimeError`.
Tests:
- R025-T01: With `TELLER_DB_PASSWORD` set, verify the env value is returned and libonepsa is not invoked.
- R025-T02: With `TELLER_DB_PASSWORD` unset and a profile lacking `1psa_item`, verify a `RuntimeError` is raised.

R030  Statement: Build one cached SQLAlchemy engine per process.
Design: `get_engine()` lazily creates a `postgresql+psycopg2` engine from the resolved profile and password, caching it in module state.
Tests:
- R030-T01: Patch `create_engine` and verify two `get_engine()` calls produce one engine and one underlying call.

R035  Statement: Apply profile sslmode to the connection.
Design: When profile sslmode is non-empty and not `disable`, include it in `connect_args` so Supabase TLS is enforced.
Tests:
- R035-T01: Resolve a profile with `sslmode = "require"` and verify `create_engine` receives `sslmode=require` in `connect_args`.
- R035-T02: Resolve a profile with `sslmode = "disable"` and verify `connect_args` contains no `sslmode` key.

R040  Statement: Configure session search_path and optional runtime role on connect.
Design: A SQLAlchemy connect listener runs `SET search_path TO <search_path>`; when `runtime_role` is non-empty it also runs `SET ROLE` with `quote_ident` quoting.
Rationale: Local PostgreSQL uses the `teller_write` role; Supabase managed Postgres lets `runtime_role` stay empty so `SET ROLE` is skipped.
Tests:
- R040-T01: Drive the connect listener with `runtime_role = "teller_write"` and verify both `SET search_path` and `SET ROLE` execute against the cursor.
- R040-T02: Drive the connect listener with empty `runtime_role` and verify `SET ROLE` is not executed.

## Changelog

- 2026-05-21: Initial requirements for `teller_db` profile-aware engine factory.
