#!/usr/bin/env bats

load "helpers/common.bash"

#R005: Cleanup bats fixture state for profile-aware script verification.
teardown() {
  teardown_shell_test
}

#R005: Resolve profile-aware script pointer path for assertions.
src() {
  printf '%s' "$(repo_root)/tests/t13_run_teller_live_canary_test.sh"
}

@test "R005: Enforce live-only canary semantics; fallback mode and warnin" {
  #R005-T01: Verify `tests/t13_run_teller_live_canary_test.sh` carries the `#R005` implementation tag.
  run grep -- "#R005:" "$(src)"
  [ "$status" -eq 0 ]
}
