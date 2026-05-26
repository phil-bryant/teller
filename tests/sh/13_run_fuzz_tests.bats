#!/usr/bin/env bats

# Requirement test-case tags for requirements/13_run_fuzz_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "13_run_fuzz_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin" "${FIXTURE_ROOT}/tests/py/properties"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-c" ] && [[ "$*" == *"import hypothesis"* ]]; then
  if [ "${STUB_HAS_HYPOTHESIS:-1}" = "1" ]; then
    exit 0
  fi
  exit 1
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pytest" ]; then
  if [ "${STUB_PYTEST_TIMEOUT:-0}" = "1" ]; then
    sleep "${STUB_PYTEST_SLEEP_SECONDS:-5}"
  fi
  test_one_pass="${STUB_TEST_ONE_PASSING:-80}"
  test_two_pass="${STUB_TEST_TWO_PASSING:-80}"
  test_one_invalid="${STUB_TEST_ONE_INVALID:-0}"
  test_two_invalid="${STUB_TEST_TWO_INVALID:-0}"
  test_one_fail="${STUB_TEST_ONE_FAILING:-0}"
  test_two_fail="${STUB_TEST_TWO_FAILING:-0}"
  cat <<PYTEST
============================ Hypothesis Statistics =============================
tests/py/properties/test_demo_properties.py::test_property_one:

  - during generate phase (0.01 seconds):
    - ${test_one_pass} passing examples, ${test_one_fail} failing examples, ${test_one_invalid} invalid examples

  - Stopped because settings.max_examples=${STUB_EFFECTIVE_MAX_EXAMPLES:-100}


tests/py/properties/test_demo_properties.py::test_property_two:

  - during generate phase (0.01 seconds):
    - ${test_two_pass} passing examples, ${test_two_fail} failing examples, ${test_two_invalid} invalid examples

  - Stopped because settings.max_examples=${STUB_EFFECTIVE_MAX_EXAMPLES:-100}
PYTEST
  exit "${STUB_PYTEST_EXIT:-0}"
fi
if [ "${1:-}" = "-" ]; then
  exec /usr/bin/python3 "$@"
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
  run env FUZZ_MAX_EXAMPLES=100 FUZZ_MIN_PROPERTY_TESTS=2 FUZZ_MIN_PER_TEST_RATIO_PERCENT=80 bash -c "cd '${TEST_TMPDIR}' && bash '${FIXTURE_ROOT}/13_run_fuzz_tests.sh'"
  [ "$status" -eq 0 ]
}

@test "fails when teller-venv python is unavailable" {
  #R005-T01
  rm -rf "${FIXTURE_ROOT}/teller-venv"
  run bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"teller-venv python is required"* ]]
}

@test "fails when hypothesis import check fails" {
  run env STUB_HAS_HYPOTHESIS=0 bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hypothesis is required in teller-venv but was not found"* ]]
}

@test "fails on pytest timeout" {
  #R025-T01
  run env STUB_PYTEST_TIMEOUT=1 FUZZ_TIMEOUT_SECONDS=1 bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"timed out after"* ]]
}

@test "fails when passing example budget is under configured floor" {
  #R020-T01
  run env STUB_TEST_ONE_PASSING=10 STUB_TEST_TWO_PASSING=10 FUZZ_MAX_EXAMPLES=100 FUZZ_MIN_PROPERTY_TESTS=2 FUZZ_MIN_TOTAL_EXAMPLES=160 bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Total passing examples 20 is below budget 160"* ]]
}

@test "fails when pytest exits non-zero and writes replay log" {
  #R030-T01
  run env STUB_PYTEST_EXIT=1 FUZZ_MAX_EXAMPLES=100 FUZZ_MIN_PROPERTY_TESTS=2 FUZZ_MIN_TOTAL_EXAMPLES=100 bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Property-based fuzz tests reported pytest failures"* ]]
  [[ "$output" == *"Failure replay log:"* ]]
  [ -f "${FIXTURE_ROOT}/artifacts/fuzz/fuzz-failure-last.log" ]
}

@test "writes fuzz summary report and passes with non-zero default gates" {
  #R015-T01
  run env STUB_TEST_ONE_PASSING=80 STUB_TEST_TWO_PASSING=80 FUZZ_MAX_EXAMPLES=100 FUZZ_MIN_PROPERTY_TESTS=2 FUZZ_MIN_PER_TEST_RATIO_PERCENT=80 bash "${FIXTURE_ROOT}/13_run_fuzz_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/fuzz/fuzz-summary.json" ]
  [ -d "${FIXTURE_ROOT}/artifacts/cache/hypothesis" ]
  [[ "$output" == *"✅ PASS: Property-based fuzz tests completed"* ]]
  run /usr/bin/python3 -c "import json,sys; s=json.load(open(sys.argv[1], encoding='utf-8')); assert s['property_test_count']==2; assert s['total_passing_examples']==160; assert s['budget_failed'] is False; assert s['gate_failed'] is False; assert s['underfilled_property_tests']==[]" "${FIXTURE_ROOT}/artifacts/fuzz/fuzz-summary.json"
  [ "$status" -eq 0 ]
}
