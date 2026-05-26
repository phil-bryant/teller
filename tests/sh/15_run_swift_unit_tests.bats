#!/usr/bin/env bats

# Requirement test-case tags for requirements/15_run_swift_unit_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "15_run_swift_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh" <<'EOF'
#!/usr/bin/env bash
echo "RUN_SHELL_TESTS=${RUN_SHELL_TESTS:-} RUN_PYTHON_TESTS=${RUN_PYTHON_TESTS:-} RUN_SQL_TESTS=${RUN_SQL_TESTS:-} RUN_SWIFT_TESTS=${RUN_SWIFT_TESTS:-}" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh"
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001
  run bash -c "cd '${TEST_TMPDIR}' && '${FIXTURE_ROOT}/15_run_swift_unit_tests.sh'"
  [ "$status" -eq 0 ]
}

@test "enables only the expected lane" {
  #R005
  run bash -c "cd '${FIXTURE_ROOT}' && ./15_run_swift_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=true"* ]]
}
