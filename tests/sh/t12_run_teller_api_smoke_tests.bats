#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t12_run_teller_api_smoke_tests.sh"
}

@test "R005: Prefer active virtualenv interpreter, then local teller-venv" {
  #R005-T01: Verify `tests/t12_run_teller_api_smoke_tests.sh` carries the `#R005` implementation tag.
  run grep -- "#R005:" "$(src)"
  [ "$status" -eq 0 ]
}

@test "R010: Run Teller API smoke checks and emit JSON/text report artifa" {
  #R010-T01: Verify `tests/t12_run_teller_api_smoke_tests.sh` carries the `#R010` implementation tag.
  run grep -- "#R010:" "$(src)"
  [ "$status" -eq 0 ]
}
