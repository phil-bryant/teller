# t03 run static security tests Wrapper Requirements

## Scope

Applies to `tests/t03_run_static_security_tests.sh`, `src/scripts/security/common.sh`,
and `src/scripts/security/run_static_security_lane.sh`.

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
Design: Use `exec "${RUNNER_HOME}/tests/t03_run_static_security_tests.sh" "$@"` so arguments pass through unchanged.
Tests:
- R015-T01: Verify wrapper source delegates to `tests/t03_run_static_security_tests.sh` with `"$@"`.

R020  Statement: Wrapper preserves runner static-lane completion marker behavior.
Design: Delegate unchanged to the runner static security golden so completion output contracts remain intact.
Tests:
- R020-T01: Verify wrapper source preserves runner static-lane delegation behavior.

R025  Statement: Wrapper preserves runner Ruff report artifact behavior.
Design: Delegate unchanged to the runner static security golden so Ruff artifact handling remains intact.
Tests:
- R025-T01: Verify wrapper source preserves runner Ruff artifact delegation behavior.

R030  Statement: Wrapper preserves runner centralized SAST gate behavior.
Design: Delegate unchanged to the runner static security golden so centralized gate policy remains intact.
Tests:
- R030-T01: Verify wrapper source preserves runner SAST gate delegation behavior.

R035  Statement: Wrapper preserves runner scanner exclusion behavior.
Design: Delegate unchanged to the runner static security golden so scanner exclusion policy remains intact.
Tests:
- R035-T01: Verify wrapper source preserves runner exclusion delegation behavior.

R040  Statement: Wrapper preserves runner gitleaks tracked-source behavior.
Design: Delegate unchanged to the runner static security golden so tracked-source scanning remains intact.
Tests:
- R040-T01: Verify wrapper source preserves runner gitleaks delegation behavior.

R045  Statement: Wrapper preserves runner Semgrep status visibility behavior.
Design: Delegate unchanged to the runner static security golden so Semgrep status output remains intact.
Tests:
- R045-T01: Verify wrapper source preserves runner Semgrep status delegation behavior.

R047  Statement: Wrapper preserves runner unsuppressed Semgrep invocation behavior.
Design: Delegate unchanged to the runner static security golden so quiet-mode suppression is not introduced.
Tests:
- R047-T01: Verify wrapper source preserves runner Semgrep invocation delegation behavior.

R050  Statement: Wrapper preserves runner Bandit status visibility behavior.
Design: Delegate unchanged to the runner static security golden so Bandit status output remains intact.
Tests:
- R050-T01: Verify wrapper source preserves runner Bandit delegation behavior.

R055  Statement: Wrapper preserves runner pip-audit status visibility behavior.
Design: Delegate unchanged to the runner static security golden so pip-audit status output remains intact.
Tests:
- R055-T01: Verify wrapper source preserves runner pip-audit delegation behavior.

R060  Statement: Wrapper preserves runner detect-secrets status visibility behavior.
Design: Delegate unchanged to the runner static security golden so detect-secrets status output remains intact.
Tests:
- R060-T01: Verify wrapper source preserves runner detect-secrets delegation behavior.

R065  Statement: Wrapper preserves runner Ruff status visibility behavior.
Design: Delegate unchanged to the runner static security golden so Ruff status output remains intact.
Tests:
- R065-T01: Verify wrapper source preserves runner Ruff status delegation behavior.

R070  Statement: Wrapper preserves runner ShellCheck status visibility behavior.
Design: Delegate unchanged to the runner static security golden so ShellCheck status output remains intact.
Tests:
- R070-T01: Verify wrapper source preserves runner ShellCheck delegation behavior.

R080  Statement: Wrapper preserves runner cache-location behavior.
Design: Delegate unchanged to the runner static security golden so cache-location policy remains intact.
Tests:
- R080-T01: Verify wrapper source preserves runner cache-location delegation behavior.

R090  Statement: Wrapper preserves runner medium-or-higher gate behavior.
Design: Delegate unchanged to the runner static security golden so blocker policy remains intact.
Tests:
- R090-T01: Verify wrapper source preserves runner gate-policy delegation behavior.

R100  Statement: Wrapper preserves runner token-redaction behavior.
Design: Delegate unchanged to the runner static security golden so token redaction remains intact.
Tests:
- R100-T01: Verify wrapper source preserves runner token-redaction delegation behavior.

R105  Statement: Wrapper preserves runner hash-pinned toolchain enforcement behavior.
Design: Delegate unchanged to the runner static security golden so hash-pin enforcement remains intact.
Tests:
- R105-T01: Verify wrapper source preserves runner hash-pin delegation behavior.

R110  Statement: Wrapper preserves runner supply-chain artifact generation behavior.
Design: Delegate unchanged to the runner static security golden so supply-chain artifact behavior remains intact.
Tests:
- R110-T01: Verify wrapper source preserves runner supply-chain delegation behavior.

R115  Statement: Wrapper preserves runner CI signing-mode default behavior.
Design: Delegate unchanged to the runner static security golden so CI signing-mode defaults remain intact.
Tests:
- R115-T01: Verify wrapper source preserves runner signing-mode delegation behavior.
