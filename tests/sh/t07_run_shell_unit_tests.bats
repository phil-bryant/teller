#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t07_run_shell_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh" <<'EOF'
#!/usr/bin/env bash
echo "RUN_SHELL_TESTS=${RUN_SHELL_TESTS:-} RUN_PYTHON_TESTS=${RUN_PYTHON_TESTS:-} RUN_SQL_TESTS=${RUN_SQL_TESTS:-} RUN_SWIFT_TESTS=${RUN_SWIFT_TESTS:-}" >> "${CALLS_LOG}"
if [[ "${FORCE_FAIL:-false}" == "true" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh"
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001-T01 #R006-T01 #R006-T02
  run bash -c "cd '${TEST_TMPDIR}' && '${FIXTURE_ROOT}/t07_run_shell_unit_tests.sh'"
  [ "$status" -eq 0 ]
  last_line="${output##*$'\n'}"
  [[ "$last_line" == "✅ Shell unit tests succeeded." ]]
}

@test "enables only the expected lane" {
  #R005-T01
  run bash -c "cd '${FIXTURE_ROOT}' && ./t07_run_shell_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"RUN_SHELL_TESTS=true RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false"* ]]
}

@test "prints final success marker on success" {
  run bash -c "cd '${FIXTURE_ROOT}' && ./t07_run_shell_unit_tests.sh"
  [ "$status" -eq 0 ]
  last_line="${output##*$'\n'}"
  [[ "$last_line" == "✅ Shell unit tests succeeded." ]]
}

@test "prints final failure marker on failure" {
  run bash -c "cd '${FIXTURE_ROOT}' && FORCE_FAIL=true ./t07_run_shell_unit_tests.sh"
  [ "$status" -eq 1 ]
  last_line="${output##*$'\n'}"
  [[ "$last_line" == "❌ Shell unit tests failed." ]]
}
