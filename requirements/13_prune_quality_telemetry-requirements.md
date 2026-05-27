# Prune Quality Telemetry Requirements

## Scope

Applies to `13_prune_quality_telemetry.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` so telemetry pruning failures surface immediately.
Tests:
- R001-T01: Verify pruning succeeds with expected output under strict mode.

R005  Statement: Execute from repository root regardless of caller working directory.
Design: Resolve `SCRIPT_DIR` from `${BASH_SOURCE[0]}` and `cd` into it before reading telemetry artifacts.
Tests:
- R005-T01: Run from a different working directory and verify default `./artifacts/telemetry` pruning still succeeds.

R010  Statement: Enforce a non-negative retention count before pruning lane summaries.
Design: Validate `QUALITY_LANE_SUMMARY_KEEP` as a non-negative integer, then prune oldest `lane-summary-*.json` files so only the newest `KEEP_COUNT` remain.
Tests:
- R010-T01: Seed four lane summaries with `QUALITY_LANE_SUMMARY_KEEP=2` and verify two oldest files are removed.
- R010-T02: Set `QUALITY_LANE_SUMMARY_KEEP` to a non-integer and verify non-zero exit with validation guidance.

## Changelog

- 2026-05-26: Initial requirements for `13_prune_quality_telemetry.sh`.
