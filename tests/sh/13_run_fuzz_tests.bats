#!/usr/bin/env bats

# Requirement test-case tags for requirements/13_run_fuzz_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "13_run_fuzz_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin" "${FIXTURE_ROOT}/tests/py"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-c" ] && [[ "$*" == *"import hypothesis"* ]]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pytest" ]; then
  echo "tests/py/test_prop.py::test_sample:"
  echo "    - 500 passing examples, 0 failing examples, 0 invalid examples"
  exit 0
fi
if [ "${1:-}" = "-" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
  shift 2
  exec "$@"
fi
if [ "${1:-}" = "-" ] && [ -f "${2:-}" ]; then
  summary_path="${3:-}"
  if [ -n "${summary_path}" ]; then
    cat > "${summary_path}" <<'JSON'
{"pytest_exit":0,"property_tests":["test_sample"],"property_test_count":1,"min_property_tests":1,"total_passing_examples":500,"total_failing_examples":0,"total_invalid_examples":0,"min_total_examples":100,"max_examples_per_test":500,"deadline_ms":1000,"pytest_failed":false,"budget_failed":false,"gate_failed":false}
JSON
  fi
  echo "Fuzz summary: property_tests=1 passing_examples=500 failing_examples=0 invalid_examples=0"
  exit 0
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"
}

teardown() {
  teardown_shell_test
}

@test "runs from non-repo cwd" {
  #R001-T01
  run bash -c "cd '${TEST_TMPDIR}' && bash '${FIXTURE_ROOT}/13_run_fuzz_tests.sh'"
  [ "$status" -eq 0 ]
}

@test "fails when teller-venv python is unavailable" {
  #R005-T01
  rm -rf "${FIXTURE_ROOT}/teller-venv"
  run bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"teller-venv python is required"* ]]
}

@test "writes fuzz summary report and passes" {
  #R015-T01
  run env FUZZ_MIN_PROPERTY_TESTS=1 FUZZ_MIN_TOTAL_EXAMPLES=100 bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/fuzz-summary.json" ]
  [[ "$output" == *"✅ PASS: Property-based fuzz tests completed"* ]]
}
