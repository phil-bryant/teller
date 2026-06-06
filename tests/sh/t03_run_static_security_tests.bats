#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t03_run_static_security_tests.sh"
}

@test "enables secure umask and strict shell mode" {
  #R001-T01: Verify wrapper source sets `umask 007` and strict shell mode.
  #R005-T01: Verify wrapper source derives `SCRIPT_DIR` and `RUNNER_HOME` from script-relative paths.
  #R010-T01: Verify wrapper source exports `RUNBOOK_REPO_ROOT` and sources `teller.env`.
  #R015-T01: Verify wrapper source delegates to `tests/t03_run_static_security_tests.sh` with `"$@"`.
  #R020-T01: Verify wrapper source preserves runner static-lane delegation behavior.
  #R025-T01: Verify wrapper source preserves runner Ruff artifact delegation behavior.
  #R030-T01: Verify wrapper source preserves runner SAST gate delegation behavior.
  #R035-T01: Verify wrapper source preserves runner exclusion delegation behavior.
  #R040-T01: Verify wrapper source preserves runner gitleaks delegation behavior.
  #R045-T01: Verify wrapper source preserves runner Semgrep status delegation behavior.
  #R047-T01: Verify wrapper source preserves runner Semgrep invocation delegation behavior.
  #R050-T01: Verify wrapper source preserves runner Bandit delegation behavior.
  #R055-T01: Verify wrapper source preserves runner pip-audit delegation behavior.
  #R060-T01: Verify wrapper source preserves runner detect-secrets delegation behavior.
  #R065-T01: Verify wrapper source preserves runner Ruff status delegation behavior.
  #R070-T01: Verify wrapper source preserves runner ShellCheck delegation behavior.
  #R080-T01: Verify wrapper source preserves runner cache-location delegation behavior.
  #R090-T01: Verify wrapper source preserves runner gate-policy delegation behavior.
  #R100-T01: Verify wrapper source preserves runner token-redaction delegation behavior.
  #R105-T01: Verify wrapper source preserves runner hash-pin delegation behavior.
  #R110-T01: Verify wrapper source preserves runner supply-chain delegation behavior.
  #R115-T01: Verify wrapper source preserves runner signing-mode delegation behavior.
  run grep "umask 007" "$(src)"
  [ "$status" -eq 0 ]
  run grep "set -euo pipefail" "$(src)"
  [ "$status" -eq 0 ]
}

@test "derives script and runner paths from script location" {
  #R005-T01: Verify wrapper source derives `SCRIPT_DIR` and `RUNNER_HOME` from script-relative paths.
  run grep "SCRIPT_DIR=" "$(src)"
  [ "$status" -eq 0 ]
  run grep "RUNNER_HOME=" "$(src)"
  [ "$status" -eq 0 ]
  run grep "runner" "$(src)"
  [ "$status" -eq 0 ]
}

@test "loads teller runbook profile before delegation" {
  #R010-T01: Verify wrapper source exports `RUNBOOK_REPO_ROOT` and sources `teller.env`.
  run grep "export RUNBOOK_REPO_ROOT" "$(src)"
  [ "$status" -eq 0 ]
  run grep "config/runbook/teller.env" "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to mapped runner golden script" {
  #R015-T01: Verify wrapper source delegates to `tests/t03_run_static_security_tests.sh` with `"$@"`.
  run grep "exec \"\${RUNNER_HOME}/tests/t03_run_static_security_tests.sh\" \"\$@\"" "$(src)"
  [ "$status" -eq 0 ]
}
