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

R290  Statement: Read file text safely.
Design: Read UTF-8 text with explicit file path handling.
Tests:
- R290-T01: Verify read_text helper is available for source checks.

R291  Statement: Read auth token payload from file path.
Design: Load token JSON and return selected token field.
Tests:
- R291-T01: Verify read_token helper is available for credential resolution.

R292  Statement: Discover candidate token sources.
Design: Discover auth token file candidates and source labels.
Tests:
- R292-T01: Verify token discovery helper is available for credential selection.

R293  Statement: Resolve cert/key file path arguments.
Design: Resolve certificate and key path inputs for live checks.
Tests:
- R293-T01: Verify cert/key resolver helper is available for live requests.

R294  Statement: Filter token candidates by institution suffix.
Design: Filter token candidates with institution-based matching.
Tests:
- R294-T01: Verify token filter helper is available for candidate narrowing.

R295  Statement: Select local token candidate to use.
Design: Select deterministic local token candidate and source.
Tests:
- R295-T01: Verify token selector helper is available for single-token mode.

R296  Statement: Resolve credentials for drift check run.
Design: Resolve env/local-token credentials and warning metadata.
Tests:
- R296-T01: Verify resolve_credentials helper is available for credential orchestration.

R297  Statement: Run one live teller API check.
Design: Execute one live endpoint request and map status result.
Tests:
- R297-T01: Verify live-check helper is available for per-endpoint checks.

R298  Statement: Collect source-derived drift checks.
Design: Collect source-derived check results in fallback mode.
Tests:
- R298-T01: Verify source-check collector helper is available for fallback reports.

R299  Statement: Discover fallback source files.
Design: Discover fallback source file candidates on disk.
Tests:
- R299-T01: Verify fallback source discovery helper is available for fallback mode.

R300  Statement: Build fallback live result payload.
Design: Build fallback result payload when live checks cannot run.
Tests:
- R300-T01: Verify fallback result helper is available for warning mode.

R301  Statement: Run authenticated live checks.
Design: Run authenticated endpoint checks with resolved credentials.
Tests:
- R301-T01: Verify authenticated live-check helper is available for live mode.

R302  Statement: Run live canary across token candidates.
Design: Execute live canary in single-token or run-all-token modes.
Tests:
- R302-T01: Verify run_live_canary orchestrator is available for live checks.

R303  Statement: Run fallback offline checks.
Design: Execute fallback checks and compute fallback status.
Tests:
- R303-T01: Verify run_fallback_checks helper is available for fallback mode.

R304  Statement: Parse teller API drift CLI arguments.
Design: Define CLI options for credentials, strictness, and outputs.
Tests:
- R304-T01: Verify parse_args helper is available for CLI parsing.

R305  Statement: Build teller API drift text report.
Design: Render mode/status/check details into text output.
Tests:
- R305-T01: Verify build_text_report helper is available for text reporting.

R306  Statement: Orchestrate drift run and exit-code policy.
Design: Run drift workflow, persist artifacts, and apply strict exits.
Tests:
- R306-T01: Verify main entrypoint is available for drift orchestration.
