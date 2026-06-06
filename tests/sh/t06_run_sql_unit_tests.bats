#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t06_run_sql_unit_tests.sh"
}

@test "R005: Execute only the SQL unit-test lane." {
  #R005-T01: Verify `tests/t06_run_sql_unit_tests.sh` carries the `#R005` implementation tag.
  run grep -- "#R005:" "$(src)"
  [ "$status" -eq 0 ]
}
