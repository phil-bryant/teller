#!/usr/bin/env bats
load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/21_run_classification_api.py"
}

@test "resolves default host and port" {
  #R001-T01
  run grep "TELLER_CLASSIFIER_API_HOST" "$(src)"
  [ "$status" -eq 0 ]
  run grep "127.0.0.1" "$(src)"
  [ "$status" -eq 0 ]
  run grep "8787" "$(src)"
  [ "$status" -eq 0 ]
}

@test "entrypoint uses uvicorn with create_app" {
  #R005-T01
  run grep "uvicorn.run" "$(src)"
  [ "$status" -eq 0 ]
  run grep "create_app" "$(src)"
  [ "$status" -eq 0 ]
}

@test "requires classifier write token lookup preflight" {
  #R010-T01 #R010-T02
  run grep "require_write_token" "$(src)"
  [ "$status" -eq 0 ]
  run grep "TELLER_CLASSIFIER_WRITE_TOKEN" "$(src)"
  [ "$status" -eq 0 ]
}

@test "fails startup path when TLS cert or key files are missing" {
  #R015-T01 #R015-T02
  run grep "HTTPS mode requires readable TLS cert/key files" "$(src)"
  [ "$status" -eq 0 ]
  run grep "TELLER_CLASSIFIER_TLS_CERT_FILE" "$(src)"
  [ "$status" -eq 0 ]
  run grep "TELLER_CLASSIFIER_TLS_KEY_FILE" "$(src)"
  [ "$status" -eq 0 ]
}

@test "allows explicit insecure HTTP override" {
  run grep "TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP" "$(src)"
  [ "$status" -eq 0 ]
  run grep 'return ("http", None, None)' "$(src)"
  [ "$status" -eq 0 ]
}
