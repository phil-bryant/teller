# Teller DB Profile Requirements

## Scope

Applies to `src/teller/teller_db_profile.py`.

R001  Statement: Expose a resolved DB profile to the engine factory.
Design: `resolve_profile()` returns a frozen `ResolvedProfile` dataclass with dialect-aware fields, including PostgreSQL connection metadata and SQLite file-path metadata, while preserving profile-name resolution semantics.
Rationale: Centralizes connection metadata so a single switch (profile name) flips between local PostgreSQL, Supabase, and SQLite without code edits.
Tests:
- R001-T01: Resolve with no profile file present and verify a `ProfileError` explains how to create `config/db-profiles.json` from `config/db-profiles-EXAMPLE.json`.

R005  Statement: Search the canonical profile-file locations in order.
Design: Resolution checks `TELLER_DB_PROFILE_FILE`, then `~/.teller/db_profiles.json`, then `./config/db-profiles.local.json`, then `./config/db-profiles.json`; the first existing file wins.
Tests:
- R005-T01: Point `TELLER_DB_PROFILE_FILE` at a temp file and verify it is loaded ahead of repo defaults.
- R005-T02: With no file at any candidate path, verify resolution fails fast with profile-setup guidance.

R010  Statement: Validate profile records and reject malformed ones.
Design: PostgreSQL-family profiles validate host/port/dbname/user and sslmode; SQLite profiles validate a non-empty database path and ignore PostgreSQL-only fields.
Tests:
- R010-T01: Load a profile missing `host` and verify a `ProfileError` is raised.
- R010-T02: Load a profile with `sslmode = "bogus"` and verify a `ProfileError` is raised.

R015  Statement: Select the active profile by name with override precedence.
Design: `TELLER_DB_PROFILE` env var beats the file's `default_profile` field; if neither is present, raise `ProfileError` instead of falling back.
Tests:
- R015-T01: With `TELLER_DB_PROFILE=supabase` and a file whose `default_profile` is `local`, verify the supabase profile is resolved.

R020  Statement: Honor existing `TELLER_DB_*` env vars as overrides.
Design: After loading the profile, apply PostgreSQL overrides (`TELLER_DB_HOST/PORT/NAME/USER/ROLE/SSLMODE/SEARCH_PATH`) and SQLite path override (`TELLER_DB_SQLITE_PATH`) when active target is SQLite.
Rationale: Existing bats tests and shell scripts that set these vars must keep working unchanged.
Tests:
- R020-T01: Resolve with the local profile and `TELLER_DB_HOST=remote.example` set; verify host is overridden but other fields come from the profile.
- R020-T02: Resolve with `TELLER_DB_USER=custom_user` set; verify only the runtime user field is overridden.

R021  Statement: Treat the `sqlite` profile name as authoritative for SQLite runtime resolution.
Design: If the selected profile name is `sqlite`, coerce the resolved profile to SQLite semantics even when upstream 1psa/env target metadata reports `local`; set `target=sqlite`, clear PostgreSQL connection fields, force `sslmode=disable`, and provide a default sqlite path when absent.
Rationale: Prevents runtime drift where shell scripts route to SQLite but Python persistence resolves PostgreSQL and attempts `psycopg2` connections.
Tests:
- R021-T01: Resolve with `default_profile=sqlite` while source fields report `target=local`; verify `target=sqlite` with default sqlite file path semantics.

## Changelog

- 2026-05-30: Extended requirements for multi-backend profile resolution including SQLite.
- 2026-05-30: Added sqlite-profile-name coercion requirement to keep Python runtime resolution aligned with script routing.
- 2026-05-21: Initial requirements for `teller_db_profile` resolver.
