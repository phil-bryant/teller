# Capture Teller Token Requirements

## Scope

Applies to `07_capture_teller_token.sh`.

R050  Statement: Default invocation launches local enrollment manager mode.
Design: Empty mode and `--connect` run capture server in `manage` mode.
Tests:
- Run script with no arguments and verify manage mode launch.

R055  Statement: List mode must print discovered enrollment contexts.
Design: Enumerate default and suffixed token/enrollment files and print a table.
Tests:
- Create multiple context files and verify each context appears in list output.

R060  Statement: Delete mode must remove only selected local context reversibly.
Design: Resolve a single context via selectors and move files to Trash with timestamp.
Constraints:
- Deletion requires explicit confirmation unless `--yes` is provided.
Tests:
- Delete one context and verify files moved under Trash path.

R065  Statement: Reconnect mode must repair selected enrollment in place.
Design: Resolve selected context and run capture server with enrollment id in `capture` mode.
Tests:
- Run `--reconnect` with valid selector and verify output files are updated.

R070  Statement: Add mode must capture a new context without overwriting existing ones.
Design: Capture to temporary files, derive/sanitize suffix, then move to unique suffixed paths.
Tests:
- Run `--add` twice for same institution and verify second context gets unique suffix.

R075  Statement: Token capture inputs must support manual, clipboard, and direct argument flows.
Design: Accept `--manual`, `--clipboard`, or first positional token; validate token; write auth file.
Tests:
- Provide literal token and verify `auth_token.json` contains `.current`.

R080  Statement: Accounts verification must be best-effort diagnostics.
Design: Skip with warnings when curl/jq/cert/key/token prerequisites are missing.
Tests:
- Remove `jq` from PATH and verify warning path without hard failure.

R085  Statement: Selector-driven operations must fail clearly on none or ambiguous matches.
Design: Require selector for scoped actions and print discovered contexts when matching fails.
Tests:
- Provide broad selector that matches multiple contexts and verify ambiguity error.

R090  Statement: Sensitive output files must be created with restrictive permissions.
Design: Enforce `~/.teller` mode `700` and token/enrollment file modes `400`.
Tests:
- Verify new output files are mode `400` after capture flows.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `07_capture_teller_token.sh`.
