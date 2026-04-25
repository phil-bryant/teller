#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "98_destroy_database.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails clearly when 1psa is missing" {
  #R001 #R005
  run bash "${FIXTURE_ROOT}/98_destroy_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "wrong confirmation cancels before teardown commands" {
  #R010
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"

  run bash -c "printf 'nope\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Destruction cancelled"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"psql "* ]]
}

@test "successful confirmation runs cleanup and prints completion" {
  #R015 #R020 #R025
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"

  run bash -c "printf 'destroy\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleanup complete!"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"DROP DATABASE IF EXISTS prod;"* ]]
}
