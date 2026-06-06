#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t02_run_dependency_freshness_tests.sh"
}

@test "centralizes umask/strict mode via the shared pointer shim" {
  #R001-T01
  run grep "pointer_shim.sh" "$(src)"
  [ "$status" -eq 0 ]
}

@test "resolves the shim from the runner src/scripts tree" {
  #R005-T01
  run grep "runner/src/scripts" "$(src)"
  [ "$status" -eq 0 ]
}

@test "selects its runbook profile explicitly before delegation" {
  #R010-T01
  run grep 'RUNBOOK_PROFILE="teller"' "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to the mapped runner golden" {
  #R015-T01
  run grep 'delegate_golden "tests/t02_run_dependency_freshness_tests.sh" "$@"' "$(src)"
  [ "$status" -eq 0 ]
}
