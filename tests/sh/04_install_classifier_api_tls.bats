#!/usr/bin/env bats

# Requirement test-case tags for requirements/04_install_classifier_api_tls-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/04_install_classifier_api_tls.sh"
}

@test "defines default classifier TLS cert and key paths under ~/.teller" {
  #R001
  run grep "classifier-localhost-cert.pem" "$(src)"
  [ "$status" -eq 0 ]
  run grep "classifier-localhost-key.pem" "$(src)"
  [ "$status" -eq 0 ]
}

@test "skips regeneration when cert and key already exist" {
  #R005
  run grep "already present; no changes made" "$(src)"
  [ "$status" -eq 0 ]
}

@test "prefers mkcert when available" {
  #R010
  run grep "command -v mkcert" "$(src)"
  [ "$status" -eq 0 ]
  run grep "mkcert -cert-file" "$(src)"
  [ "$status" -eq 0 ]
}

@test "falls back to openssl self-signed generation" {
  #R015
  run grep "command -v openssl" "$(src)"
  [ "$status" -eq 0 ]
  run grep "openssl req" "$(src)"
  [ "$status" -eq 0 ]
}
