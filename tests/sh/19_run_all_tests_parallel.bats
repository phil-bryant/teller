#!/usr/bin/env bats

# Requirement test-case tags for requirements/19_run_all_tests_parallel-requirements.md
# #R025-T02: Traceability anchor.
# #R025-T03: Traceability anchor.
# #R030-T02: Traceability anchor.
# #R045-T01: Traceability anchor.
# #R045-T02: Traceability anchor.
# #R050-T01: Traceability anchor.
# #R050-T02: Traceability anchor.
# #R055-T01: Traceability anchor.
# #R060-T01: Traceability anchor.

# Traceability numbered tags for requirements/19_run_all_tests_parallel-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R040-T01: Traceability anchor.
# #R050-T01: Traceability anchor.

load "helpers/common.bash"

CHECKS=(
  "00_run_requirements_traceability_tests.sh"
  "04_run_dependency_freshness_tests.sh"
  "12_run_teller_api_smoke_tests.sh"
  "05_run_av_test.sh"
  "06_run_static_security_tests.sh"
  "17_run_dynamic_security_tests.sh"
  "08_deploy_database_verification_test.sh"
  "09_run_unit_tests.sh"
  "10_run_macos_ui_regression_tests.sh"
  "11_verify_macos_crash_test.sh"
  "16_classification_persistence_verification_test.sh"
)

write_child_stub() {
  local name="$1"
  local body="$2"
  cat > "${FIXTURE_ROOT}/${name}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
${body}
EOF
  chmod +x "${FIXTURE_ROOT}/${name}"
}

write_all_child_stubs() {
  local body="$1"
  local check
  for check in "${CHECKS[@]}"; do
    write_child_stub "$check" "$body"
  done
}

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "19_run_all_tests_parallel.sh"
  export REPORT_DIR="${FIXTURE_ROOT}/reports"
  mkdir -p "$REPORT_DIR"
}

teardown() {
  teardown_shell_test
}

@test "reports pass for all eleven checks when every child succeeds" {
  #R001 #R025 #R030
  write_all_child_stubs 'echo "stub ${BASH_SOURCE[0]##*/}"; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ PASS: all parallel checks succeeded (11/11)"* ]]
  [[ "$output" == *"Timing: wall "* ]]

  local check pass_count=0
  for check in "${CHECKS[@]}"; do
    [[ "$output" == *"✅ PASS: ${check}"* ]]
    pass_count=$((pass_count + 1))
  done
  [ "$pass_count" -eq 11 ]
}

@test "runs from repository root regardless of caller directory" {
  #R005
  write_all_child_stubs 'echo "cwd=$(pwd)" >> "'"${CALLS_LOG}"'"; exit 0'

  run bash -c "cd '${TEST_TMPDIR}' && PARALLEL_CHECKS_REPORT_DIR='${REPORT_DIR}' bash '${FIXTURE_ROOT}/19_run_all_tests_parallel.sh'"
  [ "$status" -eq 0 ]

  local invocations
  invocations="$(<"${CALLS_LOG}")"
  [[ "$invocations" == *"cwd=${FIXTURE_ROOT}"* ]]
  while IFS= read -r line; do
    [[ "$line" == cwd="${FIXTURE_ROOT}" ]]
  done < <(grep '^cwd=' "${CALLS_LOG}")
  [ "$(grep -c '^cwd=' "${CALLS_LOG}")" -eq 11 ]
}

@test "discovers only numbered test scripts and excludes self" {
  #R010
  write_all_child_stubs 'exit 0'
  write_child_stub "07_deploy_database.sh" 'echo "non-test-script-ran" >> "'"${CALLS_LOG}"'"; exit 0'
  write_child_stub "97_backup_database.sh" 'echo "backup-script-ran" >> "'"${CALLS_LOG}"'"; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▶ Starting parallel checks (11 scripts)..."* ]]
  [[ "$output" != *"✅ PASS: 07_deploy_database.sh"* ]]
  [[ "$output" != *"✅ PASS: 19_run_all_tests_parallel.sh"* ]]
  [ ! -f "${REPORT_DIR}/07_deploy_database.log.exit" ]
  [ ! -f "${REPORT_DIR}/97_backup_database.log.exit" ]
}

@test "launches checks concurrently" {
  #R015
  write_all_child_stubs 'sleep 1; exit 0'

  start_epoch="$(date +%s)"
  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  end_epoch="$(date +%s)"
  elapsed=$((end_epoch - start_epoch))

  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 5 ]
}

@test "streams per-check results in completion order" {
  #R025
  write_all_child_stubs 'exit 0'
  write_child_stub "00_run_requirements_traceability_tests.sh" 'sleep 2; exit 0'
  write_child_stub "04_run_dependency_freshness_tests.sh" 'exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]

  local before_slow before_overall
  before_slow="${output%%✅ PASS: 04_run_dependency_freshness_tests.sh*}"
  before_overall="${output%%✅ PASS: all parallel checks succeeded*}"
  [[ "$before_slow" != *"✅ PASS: 00_run_requirements_traceability_tests.sh"* ]]
  [[ "$before_overall" == *"✅ PASS: 00_run_requirements_traceability_tests.sh"* ]]
}

@test "renders intermediate progress before all checks complete" {
  #R045
  write_all_child_stubs 'sleep 1; exit 0'
  write_child_stub "00_run_requirements_traceability_tests.sh" 'sleep 2; exit 0'
  write_child_stub "04_run_dependency_freshness_tests.sh" 'sleep 3; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    PARALLEL_CHECKS_PROGRESS_INTERVAL_SECONDS=1 \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]

  [[ "$output" == *"Progress: [0/11 (0%)]"* ]]
  [[ "$output" =~ Progress:\ \[[1-9]/11\ \([0-9]+%\)\] ]]
}

@test "prints final 100 percent progress before overall summary" {
  #R045
  write_all_child_stubs 'exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]

  local before_overall
  before_overall="${output%%✅ PASS: all parallel checks succeeded (11/11)*}"
  [[ "$before_overall" == *"Progress: [11/11 (100%)]"* ]]
  [[ "$output" == *"✅ PASS: all parallel checks succeeded (11/11)"* ]]
}

@test "waits for all checks and reports a single failed child" {
  #R020 #R025 #R030 #R035
  write_all_child_stubs 'exit 0'
  write_child_stub "09_run_unit_tests.sh" 'echo "unit-tests-failed"; exit 1'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ FAIL: 09_run_unit_tests.sh (exit 1,"* ]]
  [[ "$output" == *"see ${REPORT_DIR}/09_run_unit_tests.log"* ]]
  [[ "$output" == *"✅ PASS: 00_run_requirements_traceability_tests.sh"* ]]
  [[ "$output" == *"❌ FAIL: parallel checks: 10/11 passed"* ]]
  grep -q 'unit-tests-failed' "${REPORT_DIR}/09_run_unit_tests.log"
}

@test "writes child output to per-check log artifacts" {
  #R035
  write_all_child_stubs 'exit 0'
  write_child_stub "05_run_av_test.sh" 'echo "av-marker-12345"; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  grep -q 'av-marker-12345' "${REPORT_DIR}/05_run_av_test.log"
}

@test "child check scripts do not invoke the parallel meta-runner" {
  #R040
  local check
  local -a child_script_paths=()
  for check in "${CHECKS[@]}"; do
    copy_script_to_fixture "$check"
    child_script_paths+=("${FIXTURE_ROOT}/${check}")
  done

  run grep -l 'run_all_tests_parallel' "${child_script_paths[@]}"
  [ "$status" -ne 0 ]
}

@test "rejects concurrent orchestrator runs with an active lock" {
  #R050
  write_all_child_stubs 'sleep 2; exit 0'

  env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh" > "${TEST_TMPDIR}/first-run.log" 2>&1 &
  first_pid="$!"
  sleep 0.2

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already active"* ]]

  wait "$first_pid"
}

@test "reclaims stale lock file and succeeds" {
  #R050
  write_all_child_stubs 'exit 0'
  printf '%s\n' 999999 > "${FIXTURE_ROOT}/.19_run_all_tests_parallel.lock"

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/.19_run_all_tests_parallel.lock" ]
}

@test "terminates child checks when interrupt stop path runs" {
  #R055
  write_all_child_stubs 'sleep 60; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    PARALLEL_CHECKS_TEST_INTERRUPT=1 \
    bash "${FIXTURE_ROOT}/19_run_all_tests_parallel.sh"
  [ "$status" -eq 130 ]
  [[ "$output" == *"Interrupted; stopped parallel checks."* ]]

  local check
  for check in "${CHECKS[@]}"; do
    run pgrep -f "${FIXTURE_ROOT}/${check}"
    [ "$status" -ne 0 ]
  done
}
