#!/usr/bin/env bats

#R001: shard-3 function tag
src() {
  printf '%s' "${RUNBOOK_REPO_ROOT}/02_create_venv.sh"
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
  #R015-T01: Verify the pointer calls delegate_golden "02_create_venv.sh" with "$@".
  run grep 'delegate_golden "02_create_venv.sh" "$@"' "$(src)"
  [ "$status" -eq 0 ]
}
