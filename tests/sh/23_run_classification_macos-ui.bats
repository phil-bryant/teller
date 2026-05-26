#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

@test "deprecated wrapper execs numbered launcher" {
  run grep '24_run_classification_macos-ui.sh' "$(repo_root)/23_run_classification_macos-ui.sh"
  [ "$status" -eq 0 ]
}
