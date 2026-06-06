#!/usr/bin/env bats

load "helpers/common.bash"

#R001: Cleanup bats fixture state after script-level verification tests.
teardown() {
  teardown_shell_test
}

#R001: Resolve script-under-test pointer path for assertions.
src() {
  printf '%s' "$(repo_root)/tests/t11_run_dynamic_security_tests.sh"
}

@test "enables secure umask and strict shell mode" {
  #R001-T01: Verify wrapper source sets `umask 007` and strict shell mode.
  #R005-T01: Verify wrapper source derives `SCRIPT_DIR` and `RUNNER_HOME` from script-relative paths.
  #R010-T01: Verify wrapper source exports `RUNBOOK_REPO_ROOT` and sources `teller.env`.
  #R015-T01: Verify wrapper source delegates to `tests/t09_run_dynamic_security_tests.sh` with `"$@"`.
  #R020-T01: Verify wrapper source preserves runner dynamic-lane delegation behavior.
  #R025-T01: Verify wrapper source preserves runner DAST cleanup delegation behavior.
  #R030-T01: Verify wrapper source preserves runner ZAP-threshold delegation behavior.
  #R035-T01: Verify wrapper source preserves runner Schemathesis delegation behavior.
  #R040-T01: Verify wrapper source preserves runner port-collision delegation behavior.
  #R045-T01: Verify wrapper source preserves runner report-dir delegation behavior.
  #R050-T01: Verify wrapper source preserves runner token-redaction delegation behavior.
  #R055-T01: Verify wrapper source preserves runner hash-pin delegation behavior.
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
  #R015-T01: Verify wrapper source delegates to `tests/t09_run_dynamic_security_tests.sh` with `"$@"`.
  run grep "exec \"\${RUNNER_HOME}/tests/t09_run_dynamic_security_tests.sh\" \"\$@\"" "$(src)"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines available-port finder" {
  #R430-T01: Verify dynamic-lane source defines `find_available_tcp_port()` and port-search logic.
  run grep '^find_available_tcp_port() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines DAST cleanup trap handler" {
  #R431-T01: Verify dynamic-lane source defines `_cleanup_dast_state()` and installs it as an exit trap.
  run grep '_cleanup_dast_state() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
  run grep 'trap _cleanup_dast_state EXIT' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines gitleaks step" {
  #R432-T01: Verify dynamic-lane source defines `run_gitleaks_sast()` and gitleaks invocation arguments.
  run grep '^run_gitleaks_sast() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines shellcheck step" {
  #R433-T01: Verify dynamic-lane source defines `run_shellcheck_sast()` and ShellCheck JSON reporting.
  run grep '^run_shellcheck_sast() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines zap summary parser step" {
  #R434-T01: Verify dynamic-lane source defines `summarize_zap_html_report()` and parser invocation.
  run grep '^summarize_zap_html_report() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines matchy seeding step" {
  #R435-T01: Verify dynamic-lane source defines `seed_matchy_data_for_schemathesis()` and writes seed payload output.
  run grep 'seed_matchy_data_for_schemathesis() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines console-script usability probe" {
  #R436-T01: Verify dynamic-lane source defines `security_console_script_usable()` in toolchain bootstrap flow.
  run grep 'security_console_script_usable() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}

@test "dynamic lane defines in-use TCP port probe" {
  #R437-T01: Verify dynamic-lane source defines `is_tcp_port_in_use()` and used/free probe behavior.
  run grep '^is_tcp_port_in_use() {' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
  [ "$status" -eq 0 ]
}
