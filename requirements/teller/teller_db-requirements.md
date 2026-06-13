# Teller DB Requirements

## Scope

Applies to `src/teller/teller_db.py`.

R025  Statement: Resolve the DB password through env or libonepsa fallback.
Design: `TELLER_DB_PASSWORD` wins; otherwise `_read_password` reads from libonepsa using the resolved profile's `onepsa_item`. Empty results raise `RuntimeError`.
Tests:
- R025-T01: With `TELLER_DB_PASSWORD` set, verify the env value is returned and libonepsa is not invoked.
- R025-T02: With `TELLER_DB_PASSWORD` unset and a profile lacking `1psa_item`, verify a `RuntimeError` is raised.
- R025-T03: Verify onepsa password command safely quotes item names containing spaces.
- R025-T04: Verify libonepsa error-pointer responses raise `RuntimeError` with propagated message text.
- R025-T05: Verify null onepsa pointer responses without explicit errors raise deterministic null-password failures.
- R025-T06: Verify onepsa read failures fall back to profile env-file password fields.
- R025-T07: Verify keyboard interrupts during onepsa reads are re-raised without suppression.

R030  Statement: Build one cached SQLAlchemy engine per process.
Design: `get_engine()` lazily creates a SQLAlchemy engine from the resolved profile, using PostgreSQL settings for postgres/supabase targets and SQLite settings for sqlite target, caching it in module state.
Tests:
- R030-T01: Patch `create_engine` and verify two `get_engine()` calls produce one engine and one underlying call.
- R030-T02: Resolve SQLite profile and verify `get_engine()` builds sqlite engine without password lookup.
- R030-T03: Resolve PostgreSQL profile and verify DSN/user/password wiring feeds the engine factory.
- R030-T04: Verify sqlite-memory profile resolution still returns a cached engine instance.

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
- R040-T03: Drive the SQLite connect listener path and verify PostgreSQL session statements are skipped.

R045  Statement: Harden the sqlite/SQLCipher connection path for filesystem and DBAPI variance.
Design: `_prepare_sqlite_path` normalizes/absolutizes the sqlite path and creates its parent directory before ATTACH; `_SqlcipherConnectionAdapter` adapts pysqlcipher connections to sqlite3's optional `deterministic` callback API, retrying `create_function` without the kwarg on older builds.
Tests:
- R045-T01: sqlite creator ensures the parent directory exists before ATTACH.
- R045-T02: SQLCipher adapter retries create_function without deterministic kwarg.

## Changelog

- 2026-06-12: Documented R045 sqlite path/adapter hardening (tags already present in source/tests).
- 2026-05-30: Extended engine requirements to include SQLite target behavior.
- 2026-05-21: Initial requirements for `teller_db` profile-aware engine factory.
