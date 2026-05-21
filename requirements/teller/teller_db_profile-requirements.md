# Teller DB Profile Requirements

## Scope

Applies to `teller/teller_db_profile.py`.

R001  Statement: Expose a resolved DB profile to the engine factory.
Design: `resolve_profile()` returns a frozen `ResolvedProfile` dataclass with host, port, dbname, user, onepsa_item, search_path, runtime_role, and sslmode.
Rationale: Centralizes connection metadata so a single switch (profile name) flips between local PostgreSQL and Supabase without code edits.
Tests:
- R001-T01: Resolve with no profile file present and verify the built-in `local` profile fields are returned.

R005  Statement: Search the canonical profile-file locations in order.
Design: Resolution checks `TELLER_DB_PROFILE_FILE`, then `~/.teller/db_profiles.json`, then `./db-profiles.local.json`, then `./db-profiles.json`; the first existing file wins.
Tests:
- R005-T01: Point `TELLER_DB_PROFILE_FILE` at a temp file and verify it is loaded ahead of repo defaults.
- R005-T02: With no file at any candidate path, verify resolution falls back to the built-in `local` profile.

R010  Statement: Validate profile records and reject malformed ones.
Design: Required keys (`host`, `port`, `dbname`, `user`) must be non-empty; `port` must be int-coercible; `sslmode` must be one of disable/allow/prefer/require/verify-ca/verify-full; missing `search_path` defaults to `teller`.
Tests:
- R010-T01: Load a profile missing `host` and verify a `ProfileError` is raised.
- R010-T02: Load a profile with `sslmode = "bogus"` and verify a `ProfileError` is raised.

R015  Statement: Select the active profile by name with override precedence.
Design: `TELLER_DB_PROFILE` env var beats the file's `default_profile` field; if both are absent, `local` is selected.
Tests:
- R015-T01: With `TELLER_DB_PROFILE=supabase` and a file whose `default_profile` is `local`, verify the supabase profile is resolved.

R020  Statement: Honor existing `TELLER_DB_*` env vars as overrides.
Design: After loading the profile, override host/port/dbname/user/runtime_role/sslmode/search_path/onepsa_item from `TELLER_DB_HOST/PORT/NAME/USER/ROLE/SSLMODE/SEARCH_PATH` and `TELLER_PSA_ITEM` when set.
Rationale: Existing bats tests and shell scripts that set these vars must keep working unchanged.
Tests:
- R020-T01: Resolve with the local profile and `TELLER_DB_HOST=remote.example` set; verify host is overridden but other fields come from the profile.
- R020-T02: Resolve with `TELLER_PSA_ITEM=custom_item` set; verify `onepsa_item` is overridden.

## Changelog

- 2026-05-21: Initial requirements for `teller_db_profile` resolver.
