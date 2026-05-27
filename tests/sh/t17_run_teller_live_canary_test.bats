#!/usr/bin/env bats
load "helpers/common.bash"

copy_live_canary_project_files() {
  create_repo_fixture
  copy_script_to_fixture "t17_run_teller_live_canary_test.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/check_teller_api_drift.py" "${FIXTURE_ROOT}/src/scripts/check_teller_api_drift.py"
}

teardown() {
  teardown_shell_test
}

@test "runs strict Teller live canary wrapper with required flags" {
  #R001-T01 #R005-T01
  setup_shell_test
  copy_live_canary_project_files
  run grep -- "--require-live" "${FIXTURE_ROOT}/t17_run_teller_live_canary_test.sh"
  [ "$status" -eq 0 ]
  run grep -- "--fail-on-warn" "${FIXTURE_ROOT}/t17_run_teller_live_canary_test.sh"
  [ "$status" -eq 0 ]
  run grep -- "check_teller_api_drift.py" "${FIXTURE_ROOT}/t17_run_teller_live_canary_test.sh"
  [ "$status" -eq 0 ]
}
