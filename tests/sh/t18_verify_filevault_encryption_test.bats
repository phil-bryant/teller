#!/usr/bin/env bats
load "helpers/common.bash"

copy_filevault_project_files() {
  create_repo_fixture
  copy_script_to_fixture "t18_verify_filevault_encryption_test.sh"
}

stub_filevault_on() {
  cat > "${STUB_BIN}/filevault-status-stub" <<'EOF'
#!/usr/bin/env bash
echo "FileVault is On."
exit 0
EOF
  chmod +x "${STUB_BIN}/filevault-status-stub"
}

stub_filevault_off() {
  cat > "${STUB_BIN}/filevault-status-stub" <<'EOF'
#!/usr/bin/env bash
echo "FileVault is Off."
exit 0
EOF
  chmod +x "${STUB_BIN}/filevault-status-stub"
}

stub_filevault_status_failure() {
  cat > "${STUB_BIN}/filevault-status-stub" <<'EOF'
#!/usr/bin/env bash
echo "Unable to obtain FileVault status."
exit 1
EOF
  chmod +x "${STUB_BIN}/filevault-status-stub"
}

stub_non_darwin_uname() {
  cat > "${STUB_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
echo Linux
EOF
  chmod +x "${STUB_BIN}/uname"
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001-T01
  setup_shell_test
  copy_filevault_project_files
  stub_filevault_on
  run bash -c "cd '${TEST_TMPDIR}' && FILEVAULT_STATUS_CMD='${STUB_BIN}/filevault-status-stub' bash '${FIXTURE_ROOT}/t18_verify_filevault_encryption_test.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ FileVault encryption is enabled."* ]]
}

@test "passes when FileVault is enabled" {
  #R005-T01
  setup_shell_test
  copy_filevault_project_files
  stub_filevault_on
  run env FILEVAULT_STATUS_CMD="${STUB_BIN}/filevault-status-stub" bash "${FIXTURE_ROOT}/t18_verify_filevault_encryption_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ FileVault encryption is enabled."* ]]
}

@test "fails when FileVault is disabled" {
  #R005-T02
  setup_shell_test
  copy_filevault_project_files
  stub_filevault_off
  run env FILEVAULT_STATUS_CMD="${STUB_BIN}/filevault-status-stub" bash "${FIXTURE_ROOT}/t18_verify_filevault_encryption_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ FileVault encryption is not enabled."* ]]
  [[ "$output" == *"FileVault is Off."* ]]
}

@test "fails on non-Darwin platforms" {
  #R010-T01
  setup_shell_test
  copy_filevault_project_files
  stub_non_darwin_uname
  run bash "${FIXTURE_ROOT}/t18_verify_filevault_encryption_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ FileVault verification requires macOS."* ]]
}

@test "fails when FileVault status command fails" {
  #R015-T01
  setup_shell_test
  copy_filevault_project_files
  stub_filevault_status_failure
  run env FILEVAULT_STATUS_CMD="${STUB_BIN}/filevault-status-stub" bash "${FIXTURE_ROOT}/t18_verify_filevault_encryption_test.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ Failed to read FileVault status:"* ]]
}
