# Check PostgreSQL Freshness Requirements

## Scope

Applies to `src/scripts/check_postgres_freshness.py`.

R020  Statement: Collect PostgreSQL client/server freshness data with policy-aware gating.
Design: Discover client version via `psql --version`, optionally query server version, and evaluate minimum-version policies with a stale-component summary.
Tests:
- R020-T01: Verify client/server version parsing and stale-component gating for compliant and non-compliant versions.

R025  Statement: Evaluate CVE exposure using snapshot and policy inputs.
Design: Load snapshot/policy payloads, evaluate affected version ranges for client/server scopes, and mark gate failures when configured policy is violated.
Tests:
- R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.
