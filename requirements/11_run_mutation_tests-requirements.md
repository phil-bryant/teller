# Run Mutation Tests Requirements

## Scope

Applies to `11_run_mutation_tests.sh`.

## Ownership Boundaries

This document owns wrapper orchestration and scoring policy.
Darwin mutation-driver implementation details are owned by:
- `requirements/src/scripts/mutmut_darwin-requirements.md`

R001  Statement: Run in strict fail-fast mode from repository root.
Design: Use `umask 007`, `set -euo pipefail`, and resolve `SCRIPT_DIR` for path-independent execution.
Tests:
- R001-T01: Run script from outside repo root and verify successful execution with repo-relative paths.

R005  Statement: Fail fast when required commands are unavailable.
Design: Verify `teller-venv/bin/python3` exists and `python -m mutmut` is importable before mutation testing begins. Emit guidance referencing `./02_create_venv.sh` and `./03_load_requirements.sh` on failure.
Tests:
- R005-T01: Remove `teller-venv` and verify missing-interpreter failure guidance.

R010  Statement: Require Python unit tests to pass before mutation testing begins.
Design: Default preflight behavior is environment-sensitive: local runs default to skip (`MUTATION_SKIP_PREFLIGHT=true`), while CI defaults to preflight enabled (`MUTATION_SKIP_PREFLIGHT=false`). When enabled, run pytest preflight first and abort on failure.
Tests:
- R010-T01: Force preflight pytest failure and verify abort guidance references `./10_run_python_unit_tests.sh`.

R015  Statement: Run mutmut mutation testing across configured teller modules.
Design: Invoke mutmut from repository root while staging runtime mutant output directly under `${MUTATION_WORK_DIR:-${REPORT_DIR}/mutants}` and copy `mutmut-cicd-stats.json` into `${REPORT_DIR}`.
Tests:
- R015-T01: Stub successful mutmut execution and verify summary/stats reports are written.

R020  Statement: Gate on a configurable minimum mutation score threshold.
Design: Compute score as `killed / (killed + survived) * 100` and compare against `MUTATION_SCORE_THRESHOLD` (default `95`).
Tests:
- R020-T01: Traceability anchor in shell tests.

R022  Statement: Gate on a configurable minimum mutator coverage threshold.
Design: Compute mutator coverage as `(killed + survived) / total * 100` and compare against `MUTATOR_COVERAGE_THRESHOLD` (default `90`).
Tests:
- R022-T01: Traceability anchor in shell tests.

R025  Statement: Support recording file-level exclusions in the mutation summary.
Design: Accept `MUTATION_EXCLUDE_FILES` and persist it as `excluded_files` in the summary report.
Tests:
- R025-T01: Traceability anchor in shell tests.

R030  Statement: Persist machine-readable mutation testing report.
Design: Write `${REPORT_DIR}/mutation-summary.json` with verdict counts, thresholds, failure flags, module rollups, and run metadata (`run_started_at`, `git_sha`, `duration_seconds`).
Tests:
- R030-T01: Traceability anchor in shell tests.

R035  Statement: Emit concise operator-readable pass/fail output.
Design: Print one `✅ PASS:` line on success and explicit `❌ FAIL:` lines when gates fail.
Tests:
- R035-T01: Traceability anchor in shell tests.

R040  Statement: Support timeout to prevent runaway mutation runs.
Design: Enforce `MUTATION_TIMEOUT_SECONDS` around mutation execution and fail on timeout.
Tests:
- R040-T01: Traceability anchor in shell tests.

R045  Statement: Track mutation-quality trend over time.
Design: Append one JSON line per run to `${MUTATION_HISTORY_PATH:-${REPORT_DIR}/mutation-history.ndjson}` and persist rolling 14-day medians in `${MUTATION_TREND_PATH:-${REPORT_DIR}/mutation-trend.json}`.
Tests:
- R045-T01: Traceability anchor in shell tests.

R050  Statement: Enforce strict CI behavior on host incompatibility skips.
Design: If mutmut execution is skipped because of host/runtime incompatibility, local runs emit a skipped summary and exit 0, but CI (`CI=true|1`) exits non-zero.
Tests:
- R050-T01: Traceability anchor in shell tests.

R055  Statement: Support optional survivor budget gating.
Design: When `MUTATION_SURVIVOR_BUDGET` is set, fail the run if `survived` exceeds the budget.
Tests:
- R055-T01: Traceability anchor in shell tests.
