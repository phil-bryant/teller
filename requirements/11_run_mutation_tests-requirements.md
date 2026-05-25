# Run Mutation Tests Requirements

## Scope

Applies to `11_run_mutation_tests.sh`.

R001  Statement: Run in strict fail-fast mode from repository root.
Design: Use `umask 007`, `set -euo pipefail`, and resolve `SCRIPT_DIR` for path-independent execution.

R005  Statement: Fail fast when required commands are unavailable.
Design: Verify `teller-venv/bin/python3` exists and `python -m mutmut` is importable before mutation testing begins. Emit guidance referencing `./02_create_venv.sh` and `./03_load_requirements.sh` on failure.

R010  Statement: Require Python unit tests to pass before mutation testing begins.
Design: By default skip preflight (`MUTATION_SKIP_PREFLIGHT=true`) and assume `./10_run_python_unit_tests.sh` already passed. When `MUTATION_SKIP_PREFLIGHT=false`, run pytest preflight first and abort on failure.

R015  Statement: Run mutmut mutation testing across configured teller modules.
Design: Invoke mutmut from repository root and export `mutants/mutmut-cicd-stats.json`, then copy it into `${REPORT_DIR}`.

R020  Statement: Gate on a configurable minimum mutation score threshold.
Design: Compute score as `killed / (killed + survived) * 100` and compare against `MUTATION_SCORE_THRESHOLD` (default `90`).

R022  Statement: Gate on a configurable minimum mutator coverage threshold.
Design: Compute mutator coverage as `(killed + survived) / total * 100` and compare against `MUTATOR_COVERAGE_THRESHOLD` (default `70`).

R025  Statement: Support recording file-level exclusions in the mutation summary.
Design: Accept `MUTATION_EXCLUDE_FILES` and persist it as `excluded_files` in the summary report.

R030  Statement: Persist machine-readable mutation testing report.
Design: Write `${REPORT_DIR}/mutation-summary.json` with verdict counts, thresholds, failure flags, and module rollups.

R035  Statement: Emit concise operator-readable pass/fail output.
Design: Print one `✅ PASS:` line on success and explicit `❌ FAIL:` lines when gates fail.

R040  Statement: Support timeout to prevent runaway mutation runs.
Design: Enforce `MUTATION_TIMEOUT_SECONDS` around mutation execution and fail on timeout.
