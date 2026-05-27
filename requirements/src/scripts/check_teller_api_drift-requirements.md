# Check Teller API Drift Requirements

## Scope

Applies to `src/scripts/check_teller_api_drift.py`.

R001  Statement: Resolve Teller credentials with predictable local-token fallback behavior.
Design: Prefer explicit environment credentials, otherwise discover `~/.teller/auth_token*.json` candidates, support suffix filtering, and surface ambiguity warnings.
Tests:
- R001-T01: Verify default discovery, institution filtering, and run-all-token candidate expansion behavior.

R005  Statement: Execute live canary checks when credentials are available and degrade safely when they are not.
Design: Run `/institutions` plus authenticated `/accounts` and `/identity` checks with mTLS/auth when available; return fallback mode with actionable warnings when dependencies or credentials are missing.
Tests:
- R005-T01: Verify live and fallback decision logic emits expected check lists and warning states.

R010  Statement: Persist API drift smoke artifacts and fail only on hard check failures.
Design: Write JSON/text reports with mode/status/checks metadata and return non-zero only when status is `fail`.
Tests:
- R010-T01: Verify report persistence and process exit behavior for passing, warning, and failing scenarios.

R015  Statement: Support strict live-canary execution mode for scheduled compatibility gates.
Design: `--require-live` fails when live canary cannot run and fallback mode is used; `--fail-on-warn` promotes warning status to a non-zero exit to force remediation in strict live lanes.
Tests:
- R015-T01: Verify `--require-live` returns non-zero when run falls back.
- R015-T02: Verify `--fail-on-warn` returns non-zero when report status is warn.
