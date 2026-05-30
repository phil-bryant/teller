# Backup Database Requirements

## Scope

Applies to `97_backup_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- R001-T01: Verify script exits on unset variable and failing command paths.

R005  Statement: Require backup dependencies before backup operations.
Design: Validate `1psa`, `pg_dump`, and `pg_dumpall` commands on PATH.
Tests:
- R005-T01: Remove `pg_dump` from PATH and verify clear failure message.

R010  Statement: Resolve postgres password from configurable 1psa item and field.
Design: Read password using `1psa -p` default or `1psa -f` override field.
Tests:
- R010-T01: Override field and verify lookup path succeeds.

R015  Statement: Refuse backup when postgres password resolves empty.
Design: Validate non-empty password before dump commands.
Tests:
- R015-T01: Force empty 1psa result and verify script exits non-zero.

R020  Statement: Create backup output directory with restricted permissions.
Design: Ensure `backups/` exists and mode is `700`.
Tests:
- R020-T01: Remove directory and verify recreation with expected permissions.

R025  Statement: Write database dump in custom format with create-database metadata.
Design: Run `pg_dump -Fc -C` into timestamped `.dump` file.
Tests:
- R025-T01: Verify output `.dump` file exists with timestamped naming.

R030  Statement: Write globals-only dump for roles and grants.
Design: Run `pg_dumpall --globals-only` into matching `_globals.sql` file.
Tests:
- R030-T01: Verify globals file exists beside database dump.

R035  Statement: Restrict backup file permissions and print output paths.
Design: Apply mode `600` to output files and print their locations.
Tests:
- R035-T01: Verify file modes and output lines after successful run.

R055  Statement: Emit integrity manifest for full local backup dump/globals pairs.
Design: After writing local `.dump` and `_globals.sql`, generate sibling `*.manifest.sha256` containing sha256 checksums for both files; print manifest path and restrict manifest file permissions to `600`.
Tests:
- R055-T01: Verify full local backup writes `*.manifest.sha256` with both filenames and mode `600`.
- R055-T02: Verify output includes `Manifest written:` line with manifest path.

R040  Statement: Resolve the active DB profile via the shared `src/scripts/db_profile_export.sh` helper and refuse to back up when the helper is missing.
Design: Source whitelisted `PROFILE_NAME`/`PROFILE_TARGET`/`PG_*` exports from the helper before any dump runs; require non-empty `PROFILE_NAME`, `PROFILE_TARGET`, `PG_DBNAME`; encode the resolved profile name into the backup basename so dumps across targets do not collide.
Tests:
- R040-T01: Verify local-target run uses the resolved profile and the backup basename includes `<profile>_<db>_<timestamp>` (e.g. `local_prod_...`).
- R040-T02: Verify managed-target run encodes `<profile>_<db>_<timestamp>` (e.g. `supabase_direct_postgres_...`) when the profile resolves to managed.

R041  Statement: Support SQLite backups through the existing backup entrypoint.
Design: When `PROFILE_TARGET=sqlite`, back up the resolved SQLite database file and emit the same completion lines expected by operators.
Tests:
- R041-T01: Verify sqlite-target run writes a timestamped backup artifact without invoking `pg_dump`/`pg_dumpall`.

R045  Statement: Managed-target backup uses the profile's connection user against the direct (non-pooler) host and skips globals because managed targets do not expose role/grant state.
Design: When `PROFILE_TARGET=managed`, re-resolve via the `supabase_direct` profile, read the connection password from `PG_ONEPSA_ITEM` via `1psa` (with `TELLER_DB_PASSWORD` env override), and run a schema-scoped `pg_dump -Fc -n <PG_SEARCH_PATH>`; skip `pg_dumpall` and print an explicit `Globals skipped:` line so the operator knows full restore is unavailable on managed targets.
Tests:
- R045-T01: Verify managed-target run invokes `pg_dump -n teller` (or the resolved `PG_SEARCH_PATH`) instead of a full-database dump.
- R045-T02: Verify managed-target run prints `Globals skipped:` and does not call `pg_dumpall`.

R050  Statement: Honor existing `DATABASE_NAME` env override for backward compatibility on local-target runs while defaulting to the profile-resolved `PG_DBNAME`.
Design: For local-target runs, set `DATABASE_NAME="${DATABASE_NAME:-$PG_DBNAME}"` so callers that previously pinned `DATABASE_NAME=prod` keep working, while operators on alternative local DBs pick up the resolved profile DB by default.
Tests:
- R050-T01: Verify local-target run defaults `DATABASE_NAME` from the profile-resolved `PG_DBNAME` when no env override is set.

## Changelog

- 2026-05-30: Added R041 for SQLite backup behavior through existing script.
- 2026-05-30: Updated R020/R035 to owner-only defaults and added R055 for dump/globals manifest generation.
- 2026-05-26: Added R040/R045/R050 for profile-aware backup behavior; managed-target schema-scoped dumps and env-override compatibility.
- 2026-04-19: Initial reverse-engineered requirements for `97_backup_database.sh`.
