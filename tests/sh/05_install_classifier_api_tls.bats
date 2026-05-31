#!/usr/bin/env bats

load "helpers/common.bash"

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/05_install_classifier_api_tls.sh"
}

@test "defines default classifier TLS cert and key paths under ~/.teller" {
  #R001-T01
  run grep "classifier-localhost-cert.pem" "$(src)"
  [ "$status" -eq 0 ]
  run grep "classifier-localhost-key.pem" "$(src)"
  [ "$status" -eq 0 ]
}

@test "skips regeneration when cert and key already exist" {
  #R005-T01
  run grep "already installed; no changes made" "$(src)"
  [ "$status" -eq 0 ]
}

@test "prints generate messaging only after already-installed check" {
  #R005-T02
  run awk '
    /already installed; no changes made/ { noop_line=NR }
    /Generating local classifier API TLS materials/ { generate_line=NR }
    END {
      if (!noop_line || !generate_line) exit 1
      exit (noop_line < generate_line ? 0 : 1)
    }
  ' "$(src)"
  [ "$status" -eq 0 ]
}

@test "replaces legacy self-signed cert before mkcert generation" {
  #R005-T03
  run grep "Replacing legacy self-signed TLS cert/key with mkcert-trusted material" "$(src)"
  [ "$status" -eq 0 ]
  run grep "cert_is_self_signed" "$(src)"
  [ "$status" -eq 0 ]
}

@test "generates certs only via mkcert" {
  #R010-T01
  run grep "command -v mkcert" "$(src)"
  [ "$status" -eq 0 ]
  run grep "mkcert -cert-file" "$(src)"
  [ "$status" -eq 0 ]
}

@test "fails clearly when mkcert is missing" {
  #R010-T02
  run grep "mkcert is required but not available on PATH" "$(src)"
  [ "$status" -eq 0 ]
  run grep "01_install_prerequisites.sh" "$(src)"
  [ "$status" -eq 0 ]
}

@test "does not include openssl self-signed generation fallback" {
  #R010-T03
  run grep "openssl req" "$(src)"
  [ "$status" -eq 1 ]
  run grep "self-signed TLS cert/key via openssl" "$(src)"
  [ "$status" -eq 1 ]
}
