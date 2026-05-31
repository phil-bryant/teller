# Validate Quality Target Requirements

## Scope

Applies to `13_validate_quality_target.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` so validation failures propagate immediately.
Tests:
- R001-T01: Verify the script defines `set -euo pipefail`.

R005  Statement: Execute from repository root regardless of caller working directory.
Design: Resolve `SCRIPT_DIR` from `${BASH_SOURCE[0]}` and `cd` into it before reading telemetry history.
Tests:
- R005-T01: Verify the script resolves `SCRIPT_DIR` and changes directory to it.

R010  Statement: Fail with actionable guidance when quality history is missing.
Design: If `quality-history.ndjson` does not exist under `QUALITY_TELEMETRY_DIR` (default `./artifacts/telemetry`), print a failure message to stderr that names the missing path and instructs operators to run `./11_run_all_tests_parallel.sh` over time.
Tests:
- R010-T01: Run without a history file and verify non-zero exit with `missing quality history` guidance.

R015  Statement: Enforce sufficient recent history before declaring quality target success.
Design: Parse history rows as JSON objects with `run_started_at`, filter to last 21 days, and fail when fewer than two runs remain or when surviving runs do not span at least seven days.
Tests:
- R015-T01: Provide sparse recent history and verify the script fails with insufficient-history messaging.

R020  Statement: Require target attainment across consecutive ISO weeks.
Design: For recent runs, evaluate score and lane reliability thresholds (`QUALITY_TARGET_SCORE`, `QUALITY_TARGET_RELIABILITY`) and pass only when at least one qualifying run exists in two consecutive ISO weeks, including year rollover handling.
Tests:
- R020-T01: Provide two qualifying weeks and verify PASS output includes latest run context.

## Changelog

- 2026-05-26: Initial requirements for `13_validate_quality_target.sh`.
