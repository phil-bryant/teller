# 06 Run All Tests Parallel Wrapper Requirements

## Scope

Applies to `06_run_all_tests_parallel.sh`.

R001  Statement: Pointer runs with secure umask and strict shell mode via the shared shim.
Design: Source `src/scripts/pointer_shim.sh`, which sets `umask 007` and `set -euo pipefail` before delegation.
Tests:
- R001-T01: Verify the pointer sources `pointer_shim.sh`.

R005  Statement: Pointer resolves runner and repo roots through the shared shim.
Design: The sourced `pointer_shim.sh` resolves `RUNNER_HOME` and `RUNBOOK_REPO_ROOT`; the pointer locates the shim under `runner/src/scripts`.
Tests:
- R005-T01: Verify the pointer locates the shim under `runner/src/scripts`.

R010  Statement: Pointer selects its runbook profile explicitly before delegation.
Design: Set `RUNBOOK_PROFILE="teller"` so the shim sources `runner/config/runbook/teller.env` and exports `RUNBOOK_REPO_ROOT`.
Tests:
- R010-T01: Verify the pointer sets `RUNBOOK_PROFILE` to the repo profile.

R015  Statement: Pointer delegates execution to the mapped runner golden.
Design: Call `delegate_golden "07_run_all_tests_parallel.sh" "$@"` so the shim execs `${RUNNER_HOME}/07_run_all_tests_parallel.sh` with arguments passed through unchanged.
Tests:
- R015-T01: Verify the pointer calls `delegate_golden "07_run_all_tests_parallel.sh"` with `"$@"`.
- R015-T02: Verify the pointer relies on argument passthrough and adds no local `--no-ui`/`--no-mutation`/`--no-av` filtering.

R020  Statement: Delegated runner uses a per-repository single-run lock.
Design: The runner golden keys its lock by `RUNBOOK_REPO_ROOT` so only one parallel run executes per repo while preventing same-repo overlap.
Tests:
- R020-T01: Verify the delegated runner golden defines `LOCK_FILE` under `${RUNBOOK_REPO_ROOT}`.
