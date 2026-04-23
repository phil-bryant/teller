#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "97_backup_database.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails when pg_dump is missing" {
  stub_cmd 1psa "echo pass"
  stub_cmd pg_dumpall "exit 0"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_dump is required"* ]]
}

@test "creates dump and globals artifacts with printed paths" {
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/pg_dump" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-f" ]]; then
    touch "$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dump"
  cat > "${STUB_BIN}/pg_dumpall" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-f" ]]; then
    touch "$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dumpall"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup written:"* ]]
  [[ "$output" == *"Globals written:"* ]]
}
