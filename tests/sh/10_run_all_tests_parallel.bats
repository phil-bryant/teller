#!/usr/bin/env bats
load "helpers/common.bash"

CHECKS=(
  "t00_run_code_quality_tests.sh"
  "t01_run_av_test.sh"
  "t02_run_dependency_freshness_tests.sh"
  "t03_run_static_security_tests.sh"
  "t04_run_requirements_traceability_tests.sh"
  "t05_deploy_database_verification_test.sh"
  "t06_run_sql_unit_tests.sh"
  "t07_run_shell_unit_tests.sh"
  "t08_run_python_unit_tests.sh"
  "t09_run_mutation_tests.sh"
  "t10_run_swift_unit_tests.sh"
  "t11_run_fuzz_tests.sh"
  "t12_run_dynamic_security_tests.sh"
  "t13_run_teller_api_smoke_tests.sh"
  "t14_run_macos_ui_regression_tests.sh"
  "t15_verify_macos_crash_test.sh"
  "t16_classification_persistence_verification_test.sh"
  "t17_run_teller_live_canary_test.sh"
)

write_child_stub() {
  local name="$1"
  local body="$2"
  mkdir -p "${FIXTURE_ROOT}/tests"
  cat > "${FIXTURE_ROOT}/tests/${name}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
${body}
EOF
  chmod +x "${FIXTURE_ROOT}/tests/${name}"
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
  copy_script_to_fixture "10_run_all_tests_parallel.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  export REPORT_DIR="${FIXTURE_ROOT}/reports"
  mkdir -p "$REPORT_DIR"
}

teardown() {
  teardown_shell_test
}

@test "reports pass for all checks when every child succeeds" {
  #R001-T01 #R025-T01 #R025-T02 #R025-T03 #R030-T01 #R030-T02 #R060-T01
  write_all_child_stubs 'echo "stub ${BASH_SOURCE[0]##*/}"; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ PASS: all parallel checks succeeded (${#CHECKS[@]}/${#CHECKS[@]})"* ]]
  [[ "$output" == *"Timing: wall "* ]]

  local check pass_count=0
  for check in "${CHECKS[@]}"; do
    [[ "$output" == *"✅ PASS: ${check}"* ]]
    pass_count=$((pass_count + 1))
  done
  [ "$pass_count" -eq "${#CHECKS[@]}" ]
}

@test "runs from repository root regardless of caller directory" {
  #R005-T01
  write_all_child_stubs 'echo "cwd=$(pwd)" >> "'"${CALLS_LOG}"'"; exit 0'

  run bash -c "cd '${TEST_TMPDIR}' && PARALLEL_CHECKS_REPORT_DIR='${REPORT_DIR}' bash '${FIXTURE_ROOT}/10_run_all_tests_parallel.sh'"
  [ "$status" -eq 0 ]

  local invocations
  invocations="$(<"${CALLS_LOG}")"
  [[ "$invocations" == *"cwd=${FIXTURE_ROOT}"* ]]
  while IFS= read -r line; do
    [[ "$line" == cwd="${FIXTURE_ROOT}" ]]
  done < <(grep '^cwd=' "${CALLS_LOG}")
  [ "$(grep -c '^cwd=' "${CALLS_LOG}")" -eq "${#CHECKS[@]}" ]
}

@test "discovers only numbered test scripts and excludes self" {
  #R010-T01
  write_all_child_stubs 'exit 0'
  write_child_stub "05_deploy_database.sh" 'echo "non-test-script-ran" >> "'"${CALLS_LOG}"'"; exit 0'
  write_child_stub "97_backup_database.sh" 'echo "backup-script-ran" >> "'"${CALLS_LOG}"'"; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▶ Starting parallel checks (${#CHECKS[@]} scripts)..."* ]]
  [[ "$output" != *"✅ PASS: 05_deploy_database.sh"* ]]
  [[ "$output" != *"✅ PASS: 10_run_all_tests_parallel.sh"* ]]
  [ ! -f "${REPORT_DIR}/05_deploy_database.log.exit" ]
  [ ! -f "${REPORT_DIR}/97_backup_database.log.exit" ]
}

@test "launches checks concurrently" {
  #R015-T01
  write_all_child_stubs 'sleep 1; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"

  [ "$status" -eq 0 ]
  [[ "$output" =~ Timing:\ wall\ ([0-9]+)s ]]
  wall_seconds="${BASH_REMATCH[1]}"
  [ "$wall_seconds" -lt $(( ${#CHECKS[@]} / 2 + 2 )) ]
}

@test "streams per-check results in completion order" {
  write_all_child_stubs 'exit 0'
  write_child_stub "t04_run_requirements_traceability_tests.sh" 'sleep 2; exit 0'
  write_child_stub "t02_run_dependency_freshness_tests.sh" 'exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]

  local before_slow before_overall
  before_slow="${output%%✅ PASS: t02_run_dependency_freshness_tests.sh*}"
  before_overall="${output%%✅ PASS: all parallel checks succeeded*}"
  [[ "$before_slow" != *"✅ PASS: t04_run_requirements_traceability_tests.sh"* ]]
  [[ "$before_overall" == *"✅ PASS: t04_run_requirements_traceability_tests.sh"* ]]
}

@test "renders intermediate progress before all checks complete" {
  #R045-T01 #R045-T02
  write_all_child_stubs 'sleep 1; exit 0'
  write_child_stub "t04_run_requirements_traceability_tests.sh" 'sleep 2; exit 0'
  write_child_stub "t02_run_dependency_freshness_tests.sh" 'sleep 3; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    PARALLEL_CHECKS_PROGRESS_INTERVAL_SECONDS=1 \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]

  [[ "$output" == *"Progress: [0/${#CHECKS[@]} (0%)]"* ]]
  [[ "$output" == *"Progress: [1/${#CHECKS[@]}"* || "$output" == *"Progress: [2/${#CHECKS[@]}"* || "$output" == *"Progress: [3/${#CHECKS[@]}"* || "$output" == *"Progress: [4/${#CHECKS[@]}"* || "$output" == *"Progress: [5/${#CHECKS[@]}"* || "$output" == *"Progress: [6/${#CHECKS[@]}"* || "$output" == *"Progress: [7/${#CHECKS[@]}"* || "$output" == *"Progress: [8/${#CHECKS[@]}"* || "$output" == *"Progress: [9/${#CHECKS[@]}"* || "$output" == *"Progress: [10/${#CHECKS[@]}"* || "$output" == *"Progress: [11/${#CHECKS[@]}"* || "$output" == *"Progress: [12/${#CHECKS[@]}"* || "$output" == *"Progress: [13/${#CHECKS[@]}"* || "$output" == *"Progress: [14/${#CHECKS[@]}"* || "$output" == *"Progress: [15/${#CHECKS[@]}"* || "$output" == *"Progress: [16/${#CHECKS[@]}"* ]]
}

@test "prints final 100 percent progress before overall summary" {
  write_all_child_stubs 'exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]

  local before_overall
  before_overall="${output%%✅ PASS: all parallel checks succeeded (${#CHECKS[@]}/${#CHECKS[@]})*}"
  [[ "$before_overall" == *"Progress: [${#CHECKS[@]}/${#CHECKS[@]} (100%)]"* ]]
  [[ "$output" == *"✅ PASS: all parallel checks succeeded (${#CHECKS[@]}/${#CHECKS[@]})"* ]]
}

@test "waits for all checks and reports a single failed child" {
  #R020-T01 #R035-T01
  write_all_child_stubs 'exit 0'
  write_child_stub "t08_run_python_unit_tests.sh" 'echo "unit-tests-failed"; exit 1'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ FAIL: t08_run_python_unit_tests.sh (exit 1,"* ]]
  [[ "$output" == *"see ${REPORT_DIR}/t08_run_python_unit_tests.log"* ]]
  [[ "$output" == *"✅ PASS: t04_run_requirements_traceability_tests.sh"* ]]
  [[ "$output" == *"❌ FAIL: parallel checks: $(( ${#CHECKS[@]} - 1 ))/${#CHECKS[@]} passed"* ]]
  grep -q 'unit-tests-failed' "${REPORT_DIR}/t08_run_python_unit_tests.log"
}

@test "writes child output to per-check log artifacts" {
  write_all_child_stubs 'exit 0'
  write_child_stub "t01_run_av_test.sh" 'echo "av-marker-12345"; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  grep -q 'av-marker-12345' "${REPORT_DIR}/t01_run_av_test.log"
}

@test "isolates classifier and DAST lanes with default parallel env" {
  write_all_child_stubs 'exit 0'
  write_child_stub "t16_classification_persistence_verification_test.sh" '
    echo "api_url=${TELLER_CLASSIFIER_API_URL:-unset}" >> "'"${CALLS_LOG}"'";
    exit 0
  '
  write_child_stub "t12_run_dynamic_security_tests.sh" '
    echo "dast_base_port=${DAST_BASE_PORT:-unset}" >> "'"${CALLS_LOG}"'";
    echo "dast_reuse_api=${DAST_REUSE_EXISTING_API:-unset}" >> "'"${CALLS_LOG}"'";
    exit 0
  '

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  grep -q '^api_url=https://127.0.0.1:8787$' "${CALLS_LOG}"
  grep -q '^dast_base_port=8788$' "${CALLS_LOG}"
  grep -q '^dast_reuse_api=false$' "${CALLS_LOG}"
}

@test "child check scripts do not invoke the parallel meta-runner" {
  #R040-T01
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
  #R050-T01 #R050-T02
  write_all_child_stubs 'sleep 2; exit 0'

  env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh" > "${TEST_TMPDIR}/first-run.log" 2>&1 &
  first_pid="$!"
  sleep 0.2

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already active"* ]]

  wait "$first_pid"
}

@test "reclaims stale lock file and succeeds" {
  write_all_child_stubs 'exit 0'
  printf '%s\n' 999999 > "${FIXTURE_ROOT}/.10_run_all_tests_parallel.lock"

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/.10_run_all_tests_parallel.lock" ]
}

@test "terminates child checks when interrupt stop path runs" {
  #R055-T01
  write_all_child_stubs 'sleep 60; exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    PARALLEL_CHECKS_TEST_INTERRUPT=1 \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 130 ]
  [[ "$output" == *"Interrupted; stopped parallel checks."* ]]

  local check
  for check in "${CHECKS[@]}"; do
    run pgrep -f "${FIXTURE_ROOT}/tests/${check}"
    [ "$status" -ne 0 ]
  done
}

@test "--no-ui skips the macOS UI regression lane" {
  #R065-T01
  write_all_child_stubs 'exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh" --no-ui
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-ui: skipping t14_run_macos_ui_regression_tests.sh"* ]]
  [[ "$output" != *"PASS: t14_run_macos_ui_regression_tests.sh"* ]]
  [[ "$output" != *"FAIL: t14_run_macos_ui_regression_tests.sh"* ]]
  local expected_total=$(( ${#CHECKS[@]} - 1 ))
  [[ "$output" == *"▶ Starting parallel checks (${expected_total} scripts)..."* ]]
  [[ "$output" == *"✅ PASS: all parallel checks succeeded (${expected_total}/${expected_total})"* ]]
  [ ! -f "${REPORT_DIR}/t14_run_macos_ui_regression_tests.log.exit" ]
}

@test "rejects unknown CLI arguments with usage guidance" {
  #R065-T02
  write_all_child_stubs 'exit 0'

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"❌ FAIL: unknown argument: --nope"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "quality telemetry scores t-prefixed lane groups from actual lane outcomes" {
  write_all_child_stubs 'exit 1'
  local telemetry_dir="${FIXTURE_ROOT}/telemetry"
  mkdir -p "${telemetry_dir}"

  run env PARALLEL_CHECKS_REPORT_DIR="${REPORT_DIR}" \
    QUALITY_TELEMETRY_DIR="${telemetry_dir}" \
    bash "${FIXTURE_ROOT}/10_run_all_tests_parallel.sh"
  [ "$status" -eq 1 ]

  run python3 - <<'PY' "${telemetry_dir}/quality-history.ndjson"
import json
import sys
from pathlib import Path

history_path = Path(sys.argv[1])
rows = [json.loads(line) for line in history_path.read_text(encoding="utf-8").splitlines() if line.strip()]
assert rows, "expected at least one telemetry row"
latest = rows[-1]
components = latest.get("components", {})
assert latest.get("score") == 0.0, f"score should be 0.0 when all lanes fail: {latest.get('score')}"
assert components.get("lane_reliability") == 0.0, components
assert components.get("behavioral_coverage") == 0.0, components
assert components.get("effectiveness_quality") == 0.0, components
assert components.get("security_runtime_quality") == 0.0, components
PY
  [ "$status" -eq 0 ]
}
