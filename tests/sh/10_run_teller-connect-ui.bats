#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "10_run_teller-connect-ui.sh"
  mkdir -p "${FIXTURE_ROOT}/teller"
  cat > "${FIXTURE_ROOT}/teller/teller_connect_token_server.py" <<EOF
#!/usr/bin/env bash
echo "capture-server \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller/teller_connect_token_server.py"
}

teardown() {
  teardown_shell_test
}

@test "default mode launches capture server in manage mode" {
  #R050 #R080
  run bash "${FIXTURE_ROOT}/10_run_teller-connect-ui.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"capture-server --port 8080 --environment development --enrollment-id  --auth-token-file ${HOME}/.teller/auth_token.json --enrollment-id-file ${HOME}/.teller/enrollment_id.txt --mode manage"* ]]
}

@test "list mode prints discovered contexts" {
  #R055
  mkdir -p "${HOME}/.teller"
  printf '{"current":"token_a"}\n' > "${HOME}/.teller/auth_token.json"
  printf 'enr_default\n' > "${HOME}/.teller/enrollment_id.txt"
  printf '{"current":"token_b"}\n' > "${HOME}/.teller/auth_token_bank_a.json"
  printf 'enr_bank_a\n' > "${HOME}/.teller/enrollment_id_bank_a.txt"

  run bash "${FIXTURE_ROOT}/10_run_teller-connect-ui.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"source"* ]]
  [[ "$output" == *"enr_default"* ]]
  [[ "$output" == *"bank_a"* ]]
}

@test "delete mode removes only selected context using --yes" {
  #R060 #R065
  mkdir -p "${HOME}/.teller"
  printf '{"current":"token_a"}\n' > "${HOME}/.teller/auth_token_bank_a.json"
  printf 'enr_bank_a\n' > "${HOME}/.teller/enrollment_id_bank_a.txt"
  printf '{"current":"token_b"}\n' > "${HOME}/.teller/auth_token_bank_b.json"
  printf 'enr_bank_b\n' > "${HOME}/.teller/enrollment_id_bank_b.txt"

  run bash "${FIXTURE_ROOT}/10_run_teller-connect-ui.sh" --delete --institution_id bank_a --yes
  [ "$status" -eq 0 ]
  [ ! -e "${HOME}/.teller/auth_token_bank_a.json" ]
  [ -e "${HOME}/.teller/auth_token_bank_b.json" ]
}

@test "positional token writes auth_token.json with restrictive mode" {
  #R070 #R075 #R090
  run bash "${FIXTURE_ROOT}/10_run_teller-connect-ui.sh" token_direct_value
  [ "$status" -eq 0 ]
  [ -f "${HOME}/.teller/auth_token.json" ]
  [[ "$(<"${HOME}/.teller/auth_token.json")" == *"token_direct_value"* ]]
  [ "$(file_mode "${HOME}/.teller/auth_token.json")" = "400" ]
}

@test "selector operations fail clearly when selector is ambiguous" {
  #R085
  mkdir -p "${HOME}/.teller"
  printf '{"current":"token_a"}\n' > "${HOME}/.teller/auth_token.json"
  printf 'enr_shared\n' > "${HOME}/.teller/enrollment_id.txt"
  printf '{"current":"token_b"}\n' > "${HOME}/.teller/auth_token_bank_a.json"
  printf 'enr_shared\n' > "${HOME}/.teller/enrollment_id_bank_a.txt"

  run bash "${FIXTURE_ROOT}/10_run_teller-connect-ui.sh" --delete --enrollment_id enr_shared
  [ "$status" -eq 0 ]
  [[ "$output" == *"ambiguous"* ]]
}
