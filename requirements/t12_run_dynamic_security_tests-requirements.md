# t12 run dynamic security tests Wrapper Requirements

## Scope

Applies to `tests/t12_run_dynamic_security_tests.sh`
and `src/scripts/security/run_dynamic_security_lane.sh`.

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
Design: Use `exec "${RUNNER_HOME}/tests/t12_run_dynamic_security_tests.sh" "$@"` so arguments pass through unchanged.
Tests:
- R015-T01: Verify wrapper source delegates to `tests/t12_run_dynamic_security_tests.sh` with `"$@"`.

R020  Statement: Wrapper preserves runner dynamic-lane completion marker behavior.
Design: Delegate unchanged to the runner dynamic security golden so completion output contracts remain intact.
Tests:
- R020-T01: Verify wrapper source preserves runner dynamic-lane delegation behavior.

R025  Statement: Wrapper preserves runner DAST baseline and cleanup behavior.
Design: Delegate unchanged to the runner dynamic security golden so baseline/cleanup behavior remains intact.
Tests:
- R025-T01: Verify wrapper source preserves runner DAST cleanup delegation behavior.

R030  Statement: Wrapper preserves runner ZAP gate-threshold behavior.
Design: Delegate unchanged to the runner dynamic security golden so ZAP gate-threshold policy remains intact.
Tests:
- R030-T01: Verify wrapper source preserves runner ZAP-threshold delegation behavior.

R035  Statement: Wrapper preserves runner Schemathesis blocking-mode behavior.
Design: Delegate unchanged to the runner dynamic security golden so Schemathesis blocking behavior remains intact.
Tests:
- R035-T01: Verify wrapper source preserves runner Schemathesis delegation behavior.

R040  Statement: Wrapper preserves runner port-collision handling behavior.
Design: Delegate unchanged to the runner dynamic security golden so API/stub collision handling remains intact.
Tests:
- R040-T01: Verify wrapper source preserves runner port-collision delegation behavior.

R045  Statement: Wrapper preserves runner Schemathesis report-dir behavior.
Design: Delegate unchanged to the runner dynamic security golden so report-dir execution behavior remains intact.
Tests:
- R045-T01: Verify wrapper source preserves runner report-dir delegation behavior.

R050  Statement: Wrapper preserves runner token-redaction behavior.
Design: Delegate unchanged to the runner dynamic security golden so Schemathesis token redaction remains intact.
Tests:
- R050-T01: Verify wrapper source preserves runner token-redaction delegation behavior.

R055  Statement: Wrapper preserves runner hash-pinned toolchain enforcement behavior.
Design: Delegate unchanged to the runner dynamic security golden so hash-pin enforcement remains intact.
Tests:
- R055-T01: Verify wrapper source preserves runner hash-pin delegation behavior.
