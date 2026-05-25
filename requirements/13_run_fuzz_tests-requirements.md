# Run Fuzz Tests Requirements

## Scope

Applies to `13_run_fuzz_tests.sh`.

R001  Statement: Run fuzz tests in strict fail-fast mode from repository root.
Design: Use `set -euo pipefail`, resolve script directory, and execute pytest with Hypothesis-backed property tests.
Tests:
- R001-T01: Run script from outside repo root and verify execution succeeds with repo-relative paths.

R005  Statement: Fail fast when venv python or hypothesis is unavailable.
Design: Print actionable error when `teller-venv/bin/python3` or the `hypothesis` package is missing.
Tests:
- R005-T01: Remove `teller-venv` and verify missing-interpreter failure guidance.

R010  Statement: Fuzz Python tests with a configurable example budget.
Design: Default `FUZZ_TEST_PATHS` to `tests/py`, `FUZZ_MAX_EXAMPLES` to `500`, and `FUZZ_DEADLINE_MS` to `1000`. Pass `HYPOTHESIS_MAX_EXAMPLES` and `HYPOTHESIS_DEADLINE` into pytest. Run with `-p hypothesis` and `--hypothesis-show-statistics`.
Tests:
- R010-T01: Traceability anchor in shell tests.

R015  Statement: Emit concise success output and persist a fuzz summary report.
Design: Write `${REPORT_DIR}/fuzz-summary.json` with property test names and example counters. Print `✅ PASS:` when gates succeed.
Tests:
- R015-T01: Run fuzz lane and verify summary report plus PASS output.

R020  Statement: Gate on pytest failures and minimum fuzz example budget.
Design: Parse Hypothesis statistics from pytest output. Require at least `FUZZ_MIN_PROPERTY_TESTS` tests and `FUZZ_MIN_TOTAL_EXAMPLES` passing examples. Fail when pytest exits non-zero, timeout occurs, or the budget is not met.
Tests:
- R020-T01: Traceability anchor in shell tests.

R025  Statement: Enforce a configurable fuzz lane timeout.
Design: Wrap pytest execution with `FUZZ_TIMEOUT_SECONDS` (default `300`) and fail with diagnostics on timeout exit `124`.
Tests:
- R025-T01: Traceability anchor in shell tests.

R030  Statement: Persist machine-readable fuzz telemetry suitable for CI checks.
Design: Store property test counts plus passing/failing/invalid example totals in `fuzz-summary.json`.
Tests:
- R030-T01: Traceability anchor in shell tests.
