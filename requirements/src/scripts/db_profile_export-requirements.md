# DB Profile Export Helper Requirements

## Scope

Applies to `src/scripts/db_profile_export.sh`.

R001  Statement: Resolve DB profile metadata and emit shell-safe `KEY=value` exports.
Design: Resolve the active profile through Python helper imports and print quoted export-compatible fields for host, port, database, user, sslmode, and profile metadata.
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
