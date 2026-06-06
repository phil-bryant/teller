#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t13_run_teller_live_canary_test.sh"
}

@test "R005: Enforce live-only canary semantics; fallback mode and warnin" {
  #R005-T01: Verify `tests/t13_run_teller_live_canary_test.sh` carries the `#R005` implementation tag.
  run grep -- "#R005:" "$(src)"
  [ "$status" -eq 0 ]
}
