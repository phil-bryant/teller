#!/usr/bin/env bats

# Requirement test-case tags for requirements/18_run_classification_api-requirements.md
# #R010-T02: Traceability anchor.

# Traceability numbered tags for requirements/18_run_classification_api-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/18_run_classification_api.py"
}

@test "resolves default host and port" {
  #R001
  run grep "TELLER_CLASSIFIER_API_HOST" "$(src)"
  [ "$status" -eq 0 ]
  run grep "127.0.0.1" "$(src)"
  [ "$status" -eq 0 ]
  run grep "8787" "$(src)"
  [ "$status" -eq 0 ]
}

@test "entrypoint uses uvicorn with create_app" {
  #R005
  run grep "uvicorn.run" "$(src)"
  [ "$status" -eq 0 ]
  run grep "create_app" "$(src)"
  [ "$status" -eq 0 ]
}

@test "requires classifier write token lookup preflight" {
  #R010
  run grep "require_write_token" "$(src)"
  [ "$status" -eq 0 ]
  run grep "TELLER_CLASSIFIER_WRITE_TOKEN" "$(src)"
  [ "$status" -eq 0 ]
}
