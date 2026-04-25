#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "09_configure_teller_io.sh"
}

teardown() {
  teardown_shell_test
}

@test "creates ~/.teller with restrictive permissions and succeeds with env inputs" {
  cert_src="${TEST_TMPDIR}/cert.pem"
  key_src="${TEST_TMPDIR}/key.pem"
  printf "CERT" > "$cert_src"
  printf "KEY" > "$key_src"
  stub_cmd git "exit 0"
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '[]' > "${out}"
printf '200'
EOF
  chmod +x "${STUB_BIN}/curl"
  cat > "${STUB_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF
  chmod +x "${STUB_BIN}/jq"

  run env \
    CONFIGURE_TELLER_EXAMPLES=false \
    TELLER_APPLICATION_ID=app_test \
    TELLER_CERT_PATH="$cert_src" \
    TELLER_KEY_PATH="$key_src" \
    bash "${FIXTURE_ROOT}/09_configure_teller_io.sh"
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.teller" ]
  [ "$(file_mode "${HOME}/.teller")" = "700" ]
  [ "$(file_mode "${HOME}/.teller/application_id.txt")" = "400" ]
}

@test "prefers existing application id file over env override" {
  mkdir -p "${HOME}/.teller"
  chmod 700 "${HOME}/.teller"
  printf "app_existing" > "${HOME}/.teller/application_id.txt"
  printf "cert" > "${HOME}/.teller/certificate.pem"
  printf "key" > "${HOME}/.teller/private_key.pem"
  chmod 400 "${HOME}/.teller/application_id.txt" "${HOME}/.teller/certificate.pem" "${HOME}/.teller/private_key.pem"
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '[]' > "${out}"
printf '200'
EOF
  chmod +x "${STUB_BIN}/curl"
  stub_cmd jq "echo 0"
  stub_cmd git "exit 0"

  run env CONFIGURE_TELLER_EXAMPLES=false TELLER_APPLICATION_ID=app_new bash "${FIXTURE_ROOT}/09_configure_teller_io.sh"
  [ "$status" -eq 0 ]
  value="$(<"${HOME}/.teller/application_id.txt")"
  [ "$value" = "app_existing" ]
}

@test "fails when examples directory exists but is not a git repo" {
  mkdir -p "${TEST_TMPDIR}/bad_examples"
  run env TELLER_EXAMPLES_DIR="${TEST_TMPDIR}/bad_examples" bash "${FIXTURE_ROOT}/09_configure_teller_io.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exists but is not a git repository"* ]]
}
