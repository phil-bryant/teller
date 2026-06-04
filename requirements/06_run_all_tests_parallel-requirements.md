# 06 run all tests parallel Wrapper Requirements

## Scope

Applies to `06_run_all_tests_parallel.sh`.

R001  Statement: Wrapper runs in strict shell mode with secure umask.
Design: Configure `umask 007` and `set -euo pipefail` before any path resolution or delegation.
Tests:
- R001-T01: Verify wrapper source sets `umask 007` and strict shell mode.

R005  Statement: Wrapper resolves repository root and runner root from script location.
Design: Compute `SCRIPT_DIR` from `${BASH_SOURCE[0]}` and derive `RUNNER_HOME` from the script-relative runner path.
Tests:
- R005-T01: Verify wrapper source derives `SCRIPT_DIR` and `RUNNER_HOME` from script-relative paths.

R010  Statement: Wrapper loads teller runbook profile before delegation.
Design: Export `RUNBOOK_REPO_ROOT` and source `runner/config/runbook/teller.env` prior to `exec`.
Tests:
- R010-T01: Verify wrapper source exports `RUNBOOK_REPO_ROOT` and sources `teller.env`.

R015  Statement: Wrapper delegates execution to the mapped runner golden.
Design: Use `exec "${RUNNER_HOME}/07_run_all_tests_parallel.sh" "$@"` so arguments pass through unchanged.
Tests:
- R015-T01: Verify wrapper source delegates to `07_run_all_tests_parallel.sh` with `"$@"`.

R020  Statement: Delegated runner uses a per-repository single-run lock.
Design: Runner lock path is keyed by `RUNBOOK_REPO_ROOT` so one parallel runner may execute per repo while preventing same-repo overlap.
Tests:
- R020-T01: Verify delegated runner source defines `LOCK_FILE` under `${RUNBOOK_REPO_ROOT}`.
