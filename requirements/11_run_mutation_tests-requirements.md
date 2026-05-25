# Run Mutation Tests Requirements

## Scope

Applies to `11_run_mutation_tests.sh`.

R001  Statement: Run in strict fail-fast mode from repository root.
Design: Use `umask 007`, `set -euo pipefail`, and resolve `SCRIPT_DIR` for path-independent execution.
Tests:
- R001-T01: Run script from outside repo root and verify successful execution with repo-relative paths.

R005  Statement: Fail fast when required commands are unavailable.
Design: Verify `teller-venv/bin/python3` exists and `python -m mutmut` is importable before mutation testing begins. Emit guidance referencing `./02_create_venv.sh` and `./03_load_requirements.sh` on failure.
Tests:
- R005-T01: Remove `teller-venv` and verify missing-interpreter failure guidance.

R010  Statement: Require Python unit tests to pass before mutation testing begins.
Design: By default skip preflight (`MUTATION_SKIP_PREFLIGHT=true`) and assume `./10_run_python_unit_tests.sh` already passed. When `MUTATION_SKIP_PREFLIGHT=false`, run pytest preflight first and abort on failure.
Tests:
- R010-T01: Force preflight pytest failure and verify abort guidance references `./10_run_python_unit_tests.sh`.

R015  Statement: Run mutmut mutation testing across configured teller modules.
Design: Invoke mutmut from repository root while staging runtime mutant output directly under `${MUTATION_WORK_DIR:-${REPORT_DIR}/mutants}` and copy `mutmut-cicd-stats.json` into `${REPORT_DIR}`.
Tests:
- R015-T01: Stub successful mutmut execution and verify summary/stats reports are written.

R020  Statement: Gate on a configurable minimum mutation score threshold.
Design: Compute score as `killed / (killed + survived) * 100` and compare against `MUTATION_SCORE_THRESHOLD` (default `90`).
Tests:
- R020-T01: Traceability anchor in shell tests.

R022  Statement: Gate on a configurable minimum mutator coverage threshold.
Design: Compute mutator coverage as `(killed + survived) / total * 100` and compare against `MUTATOR_COVERAGE_THRESHOLD` (default `70`).
Tests:
- R022-T01: Traceability anchor in shell tests.

R025  Statement: Support recording file-level exclusions in the mutation summary.
Design: Accept `MUTATION_EXCLUDE_FILES` and persist it as `excluded_files` in the summary report.
Tests:
- R025-T01: Traceability anchor in shell tests.

R030  Statement: Persist machine-readable mutation testing report.
Design: Write `${REPORT_DIR}/mutation-summary.json` with verdict counts, thresholds, failure flags, and module rollups.
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
