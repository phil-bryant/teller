#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t03_run_static_security_tests.sh"
}

@test "enables secure umask and strict shell mode" {
  #R001-T01 #R005-T01 #R010-T01 #R015-T01 #R020-T01 #R025-T01 #R030-T01 #R035-T01 #R040-T01 #R045-T01 #R047-T01 #R050-T01 #R055-T01 #R060-T01 #R065-T01 #R070-T01 #R080-T01 #R090-T01 #R100-T01 #R105-T01 #R110-T01 #R115-T01
  run grep "umask 007" "$(src)"
  [ "$status" -eq 0 ]
  run grep "set -euo pipefail" "$(src)"
  [ "$status" -eq 0 ]
}

@test "derives script and runner paths from script location" {
  #R005-T01
  run grep "SCRIPT_DIR=" "$(src)"
  [ "$status" -eq 0 ]
  run grep "RUNNER_HOME=" "$(src)"
  [ "$status" -eq 0 ]
  run grep "runner" "$(src)"
  [ "$status" -eq 0 ]
}

@test "loads teller runbook profile before delegation" {
  #R010-T01
  run grep "export RUNBOOK_REPO_ROOT" "$(src)"
  [ "$status" -eq 0 ]
  run grep "config/runbook/teller.env" "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to mapped runner golden script" {
  #R015-T01
  run grep "exec \"\${RUNNER_HOME}/tests/t03_run_static_security_tests.sh\" \"\$@\"" "$(src)"
  [ "$status" -eq 0 ]
}
