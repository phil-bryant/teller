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
