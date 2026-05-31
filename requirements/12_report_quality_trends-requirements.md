# Report Quality Trends Requirements

## Scope

Applies to `12_report_quality_trends.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` to halt on setup or reporting failures.
Tests:
- R001-T01: Verify the script defines `set -euo pipefail`.

R005  Statement: Execute from repository root regardless of caller working directory.
Design: Resolve `SCRIPT_DIR` from `${BASH_SOURCE[0]}` and `cd` into it before reading telemetry paths.
Tests:
- R005-T01: Verify the script resolves `SCRIPT_DIR` and changes directory to it.

R010  Statement: Fail with actionable guidance when the trend payload is missing.
Design: If `quality-trend.json` does not exist under `QUALITY_TELEMETRY_DIR` (default `./artifacts/telemetry`), print a failure message to stderr that names the missing path and instructs operators to run `./11_run_all_tests_parallel.sh`.
Tests:
- R010-T01: Run without a trend file and verify non-zero exit with `missing trend file` guidance.

R015  Statement: Render a human-readable local trend summary from telemetry payloads.
Design: Parse `quality-trend.json` and optional `quality-history.ndjson`, print latest run/score, rolling 21-run metrics, rolling 14-day metrics, and final status line (`PASS`, `WARN`, or `FAIL`) derived from `performance_slo`.
Tests:
- R015-T01: Provide trend and history fixtures and verify summary output includes formatted latest score, rolling p95 wall metric, and expected status.

## Changelog

- 2026-05-26: Initial requirements for `12_report_quality_trends.sh`.
