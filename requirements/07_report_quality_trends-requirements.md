# 07 report quality trends Wrapper Requirements

## Scope

Applies to `07_report_quality_trends.sh`.

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
Design: Use `exec "${RUNNER_HOME}/08_report_quality_trends.sh" "$@"` so arguments pass through unchanged.
Tests:
- R015-T01: Verify wrapper source delegates to `08_report_quality_trends.sh` with `"$@"`.
