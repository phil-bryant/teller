#!/usr/bin/env bats

#R001: shard-3 function tag
src() {
  printf '%s' "${RUNBOOK_REPO_ROOT}/06_run_all_tests_parallel.sh"
}

#R001: shard-3 function tag
runner_src() {
  printf '%s' "${RUNBOOK_REPO_ROOT}/../runner/07_run_all_tests_parallel.sh"
}

#R001: shard-3 function tag
profile_path() {
  printf 'config/runbook/%s.env' "${RUNBOOK_REPO_NAME}"
}

@test "centralizes umask/strict mode via the shared pointer shim" {
  #R001-T01: Verify the pointer sources pointer_shim.sh.
  run grep "pointer_shim.sh" "$(src)"
  [ "$status" -eq 0 ]
}

@test "resolves the shim from the runner src/scripts tree" {
  #R005-T01: Verify the pointer locates the shim under runner/src/scripts.
  run grep "runner/src/scripts" "$(src)"
  [ "$status" -eq 0 ]
}

@test "selects its runbook profile explicitly before delegation" {
  #R010-T01: Verify the pointer sets RUNBOOK_PROFILE to the repo profile.
  run grep "RUNBOOK_PROFILE=\"${RUNBOOK_REPO_NAME}\"" "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to the mapped runner golden" {
  #R015-T01: Verify the pointer calls delegate_golden "07_run_all_tests_parallel.sh" with "$@".
  run grep 'delegate_golden "07_run_all_tests_parallel.sh" "$@"' "$(src)"
  [ "$status" -eq 0 ]
}

@test "forwards optional skip flags without local filtering" {
  #R015-T02: Verify the pointer relies on argument passthrough and adds no local --no-ui/--no-mutation/--no-av filtering.
  run grep '\$@' "$(src)"
  [ "$status" -eq 0 ]
  run grep -E -- '--no-ui|--no-mutation|--no-av' "$(src)"
  [ "$status" -ne 0 ]
}

@test "delegated runner lock is scoped to runbook repo root" {
  #R020-T01: Verify the delegated runner golden defines LOCK_FILE under ${RUNBOOK_REPO_ROOT}.
  run grep 'LOCK_FILE="${RUNBOOK_REPO_ROOT}/.07_run_all_tests_parallel.lock"' "$(runner_src)"
  [ "$status" -eq 0 ]
}
