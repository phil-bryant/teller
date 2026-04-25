#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "04_run_unit_tests.sh"
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001 #R005 #R010
  cat > "${STUB_BIN}/python3" <<EOF
#!/usr/bin/env bash
echo "python3 cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/python3"
  stub_cmd swift "exit 0"
  stub_cmd bats "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${TEST_TMPDIR}' && RUN_SHELL_TESTS=false RUN_SWIFT_TESTS=false '${FIXTURE_ROOT}/04_run_unit_tests.sh'"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python3 cwd=${FIXTURE_ROOT} args=-m unittest discover tests/py"* ]]
}

@test "fails with actionable message when shell tests are enabled but bats is missing" {
  #R015
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=false ./04_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bats is required"* ]]
}

@test "can disable python suite via RUN_PYTHON_TESTS=false" {
  stub_cmd bats "echo bats-run; exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
echo python-should-not-run
exit 1
EOF
  chmod +x "${STUB_BIN}/python3"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=true RUN_PYTHON_TESTS=false RUN_SWIFT_TESTS=false ./04_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "runs swift suite by default when macos tests exist" {
  #R020
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo "swift \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && ./04_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"swift test --package-path ./macos-ui"* ]]
}

@test "can disable swift suite via RUN_SWIFT_TESTS=false" {
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo swift-should-not-run
exit 1
EOF
  chmod +x "${STUB_BIN}/swift"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SWIFT_TESTS=false ./04_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}
