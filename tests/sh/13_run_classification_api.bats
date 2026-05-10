#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/13_run_classification_api.py"
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
