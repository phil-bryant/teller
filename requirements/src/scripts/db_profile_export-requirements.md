# DB Profile Export Helper Requirements

## Scope

Applies to `src/scripts/db_profile_export.sh`.

R001  Statement: Resolve DB profile metadata and emit shell-safe `KEY=value` exports.
Design: Resolve the active profile through Python helper imports and print quoted export-compatible fields for dialect, profile metadata, and backend-specific connection settings (PostgreSQL or SQLite).
Tests:
- R001-T01: Verify successful execution prints required export keys with shell-quoted values.

R005  Statement: Support explicit profile overrides and argument validation.
Design: Accept `--profile <name>`/`--profile=<name>` overrides, print usage for `--help`, and fail with status 2 on unknown arguments.
Tests:
- R005-T01: Verify profile override is propagated and unknown flags fail with an explicit error.

R010  Statement: Fail clearly when profile resolution fails.
Design: Surface `ProfileError` diagnostics to stderr and exit non-zero without emitting partial export payloads.
Tests:
- R010-T01: Simulate profile-resolution failure and verify stderr guidance plus failing exit status.

R015  Statement: Avoid exporting SQLCipher secrets by default.
Design: Default export mode must omit `SQLCIPHER_KEY`; scripts that need the key may request it explicitly via `--print-sqlcipher-key` and consume it without sourcing.
Tests:
- R015-T01: Verify default output omits SQLCIPHER key exports and explicit key mode returns the key value.
- R015-T02: Verify sqlite profile exports omit SQLCIPHER key in default export mode.
