# Check Teller API Version Freshness Requirements

## Scope

Applies to `src/scripts/check_teller_api_version_freshness.py`.

R001  Statement: Discover latest Teller API version from configured HTTPS metadata sources.
Design: Query configured docs/OpenAPI endpoints over HTTPS, parse version metadata, and record source-specific warnings when extraction fails.
Tests:
- R001-T01: Verify version discovery fallback order and warning accumulation for failed/invalid sources.

R005  Statement: Support authenticated dashboard-derived version state when 1psa credentials are configured.
Design: Optionally authenticate to the Teller dashboard using 1psa credentials/OTP, parse current/latest dashboard versions, and report explicit dashboard-check status.
Tests:
- R005-T01: Verify dashboard parsing and credential/OTP error handling paths produce expected status fields.

R010  Statement: Enforce optional baseline drift gate and persist freshness artifacts.
Design: Compare discovered latest version against configured baseline, mark `newer_available`, fail when `--fail-on-new` is set and drift exists, and always write JSON/text outputs.
Tests:
- R010-T01: Verify baseline comparisons and fail-on-new exit behavior for equal, older, and newer-version outcomes.

R310  Statement: Parse semver values and compare version ordering.
Design: Parse semantic versions and compare ordering for freshness checks.
Tests:
- R310-T01: Verify semver parse/compare helpers are available for freshness logic.

R311  Statement: Fetch JSON payloads over HTTP with timeout.
Design: Fetch JSON from version sources with timeout/error handling.
Tests:
- R311-T01: Verify JSON fetch helper is available for source discovery.

R312  Statement: Fetch text payloads via default/custom opener paths.
Design: Fetch text from URLs using default and injected openers.
Tests:
- R312-T01: Verify text fetch helpers are available for docs/dashboard parsing.

R313  Statement: Extract version values from docs text.
Design: Parse docs text for version references and return parsed value.
Tests:
- R313-T01: Verify docs version extractor helper is available for source parsing.

R314  Statement: Extract hidden form input by field name.
Design: Parse hidden input values from login/MFA forms.
Tests:
- R314-T01: Verify hidden-input extractor helper is available for dashboard flow.

R315  Statement: Resolve OTP codes from digits or otpauth URIs.
Design: Normalize digits and derive TOTP code from otpauth secrets.
Tests:
- R315-T01: Verify OTP helpers are available for MFA resolution.

R316  Statement: Read 1Password field values via CLI.
Design: Invoke 1Password CLI and read requested field values.
Tests:
- R316-T01: Verify 1psa field reader helper is available for credential loading.

R317  Statement: Extract latest/current dashboard version values.
Design: Parse dashboard text for latest and current API version values.
Tests:
- R317-T01: Verify dashboard extract helpers are available for version parsing.

R318  Statement: Decide whether dashboard is on latest version.
Design: Compare current/latest dashboard versions into on_latest status.
Tests:
- R318-T01: Verify dashboard latest-check helper is available for status computation.

R319  Statement: Build dashboard error result payload.
Design: Construct dashboard error payload with status/error details.
Tests:
- R319-T01: Verify dashboard error-result helper is available for failure paths.

R320  Statement: Load dashboard credentials from configured sources.
Design: Resolve dashboard login credentials and optional OTP sources.
Tests:
- R320-T01: Verify dashboard credential loader helper is available for auth flow.

R321  Statement: Submit dashboard login request.
Design: Submit dashboard login form and return response context.
Tests:
- R321-T01: Verify dashboard login helper is available for authenticated discovery.

R322  Statement: Submit and optionally complete dashboard MFA.
Design: Submit MFA code and complete optional MFA flow branches.
Tests:
- R322-T01: Verify dashboard MFA helpers are available for MFA handling.

R323  Statement: Apply parsed dashboard versions to result payload.
Design: Apply parsed dashboard version fields and freshness flags.
Tests:
- R323-T01: Verify dashboard version application helper is available for result shaping.

R324  Statement: Discover dashboard version via authenticated flow.
Design: Run full authenticated dashboard version discovery sequence.
Tests:
- R324-T01: Verify authenticated dashboard discovery helper is available.

R325  Statement: Parse dashboard page text into version tuple.
Design: Parse dashboard text for current/latest/on_latest fields.
Tests:
- R325-T01: Verify dashboard parser helper is available for page parsing.

R326  Statement: Discover dashboard version entrypoint behavior.
Design: Run dashboard discovery with enabled/disabled auth modes.
Tests:
- R326-T01: Verify dashboard discovery entrypoint helper is available.

R327  Statement: Discover latest version across configured sources.
Design: Resolve source list, query sources, and accumulate warnings.
Tests:
- R327-T01: Verify discover_version helper is available for source orchestration.

R328  Statement: Resolve raw version-source specification to list.
Design: Normalize raw source specs into concrete source list.
Tests:
- R328-T01: Verify version-source resolver helper is available for source setup.

R329  Statement: Compute whether newer version is available.
Design: Compute newer_available using discovered and baseline values.
Tests:
- R329-T01: Verify newer-available helper is available for drift status.

R330  Statement: Build teller API version freshness report payload.
Design: Assemble report payload across source/dashboard/baseline sections.
Tests:
- R330-T01: Verify build_report helper is available for payload assembly.

R331  Statement: Format version freshness report text output.
Design: Render report payload into operator-readable text output.
Tests:
- R331-T01: Verify format_report helper is available for text rendering.

R332  Statement: Parse teller API version freshness CLI args.
Design: Define parser options for sources, dashboard auth, and fail gates.
Tests:
- R332-T01: Verify parse_args helper is available for CLI parsing.

R333  Statement: Orchestrate version freshness run and exit policy.
Design: Run discovery workflow, write artifacts, and apply fail-on-new.
Tests:
- R333-T01: Verify main entrypoint is available for orchestration policy.
