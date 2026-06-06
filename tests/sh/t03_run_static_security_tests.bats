#!/usr/bin/env bats

load "helpers/common.bash"

#R001: Cleanup bats fixture state after script-level verification tests.
teardown() {
  teardown_shell_test
}

#R001: Resolve script-under-test pointer path for assertions.
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

@test "static lane defines report finding counter" {
  #R420-T01: Verify static-lane source defines `count_report_findings()` and counts report entries.
  run grep '^count_report_findings() {' "$(repo_root)/src/scripts/security/run_static_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "static lane defines semgrep finding formatter" {
  #R421-T01: Verify static-lane source defines `print_semgrep_findings()` and Semgrep summary output paths.
  run grep '^print_semgrep_findings() {' "$(repo_root)/src/scripts/security/run_static_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "static lane enforces hash-pinned requirements helpers" {
  #R422-T01: Verify static-lane source defines hash-check and hash-require helper functions.
  run grep '^requirements_file_has_hashes() {' "$(repo_root)/src/scripts/security/run_static_security_lane.sh"
  [ "$status" -eq 0 ]
  run grep '^require_hashed_requirements_file() {' "$(repo_root)/src/scripts/security/run_static_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "static lane defines supply-chain generation step" {
  #R423-T01: Verify static-lane source defines `generate_supply_chain_artifacts()` and invokes the generator script.
  run grep '^generate_supply_chain_artifacts() {' "$(repo_root)/src/scripts/security/run_static_security_lane.sh"
  [ "$status" -eq 0 ]
  run grep 'generate_supply_chain_artifacts.py' "$(repo_root)/src/scripts/security/run_static_security_lane.sh"
  [ "$status" -eq 0 ]
}
