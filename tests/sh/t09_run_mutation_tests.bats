#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t09_run_mutation_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin" "${FIXTURE_ROOT}/src/scripts" "${FIXTURE_ROOT}/tests/py"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "--version" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pytest" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "run" ]; then
  mkdir -p artifacts/mutation/mutants
  cat > artifacts/mutation/mutants/mutmut-cicd-stats.json <<'JSON'
{"killed":90,"survived":10,"total":100}
JSON
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "export-cicd-stats" ]; then
  mkdir -p artifacts/mutation/mutants
  cat > artifacts/mutation/mutants/mutmut-cicd-stats.json <<'JSON'
{"killed":90,"survived":10,"total":100}
JSON
  exit 0
fi
if [ "${1:-}" = "-" ] && [ -f "${2:-}" ]; then
  stats_path="${2:-}"
  summary_path="${3:-}"
  history_path="${12:-}"
  trend_path="${13:-}"
  survivor_budget="${14:-}"
  survived_count=5
  if [ -n "${summary_path}" ]; then
    cat > "${summary_path}" <<'JSON'
{"total":100,"killed":95,"survived":5,"score":95.0,"mutator_coverage":100.0,"threshold":95,"coverage_threshold":90,"gate_failed":false,"run_started_at":"2026-05-26T00:00:00Z","git_sha":"deadbee","duration_seconds":12,"by_module":{}}
JSON
  fi
  [ -f "${stats_path}" ] || cat > "${stats_path}" <<'JSON'
{"killed":95,"survived":5,"total":100}
JSON
  if [ -n "${history_path}" ]; then
    mkdir -p "$(dirname "${history_path}")"
    cat > "${history_path}" <<'JSON'
{"run_started_at":"2026-05-26T00:00:00Z","score":95.0,"mutator_coverage":100.0,"survived":5}
JSON
  fi
  if [ -n "${trend_path}" ]; then
    mkdir -p "$(dirname "${trend_path}")"
    cat > "${trend_path}" <<'JSON'
{"rolling_14d":{"runs":1,"median_score":95.0,"median_mutator_coverage":100.0}}
JSON
  fi
  if [ -n "${survivor_budget}" ] && [ "${survived_count}" -gt "${survivor_budget}" ]; then
    echo "❌ FAIL: Survived mutants ${survived_count} exceed survivor budget ${survivor_budget}."
    exit 1
  fi
  echo "✅ PASS: Mutation score 95.00% (threshold 95.0%), mutator coverage 100.00% (threshold 90.0%)."
  exit 0
fi
if [ "${1:-}" = "-" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
  shift 2
  exec "$@"
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"
  cat > "${FIXTURE_ROOT}/src/scripts/mutmut_darwin.py" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/mutmut_darwin.py"
  cat > "${FIXTURE_ROOT}/src/scripts/mutmut_darwin_stub.py" <<'EOF'
# stub
EOF
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001-T01 #R005-T01 #R010-T01 #R015-T01 #R020-T01 #R022-T01 #R025-T01 #R030-T01 #R035-T01 #R040-T01 #R045-T01 #R050-T01 #R055-T01
  run bash -c "cd '${TEST_TMPDIR}' && '${FIXTURE_ROOT}/t09_run_mutation_tests.sh'"
  [ "$status" -eq 0 ]
}

@test "fails when teller-venv python is unavailable" {
  rm -rf "${FIXTURE_ROOT}/teller-venv"
  run bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"teller-venv python is required"* ]]
}

@test "preflight failure points to python unit lane" {
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "--version" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pytest" ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"
  run env MUTATION_SKIP_PREFLIGHT=false bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"./tests/t08_run_python_unit_tests.sh"* ]]
}

@test "writes mutation summary and stats on success" {
  run bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/mutation/mutation-summary.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/mutation/mutmut-cicd-stats.json" ]
}

@test "writes run metadata and strict thresholds in mutation summary" {
  run bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  run python3 - "${FIXTURE_ROOT}/artifacts/mutation/mutation-summary.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
assert payload["threshold"] == 95
assert payload["coverage_threshold"] == 90
assert "run_started_at" in payload
assert "git_sha" in payload
assert "duration_seconds" in payload
PY
  [ "$status" -eq 0 ]
}

@test "persists mutation history and trend artifacts" {
  run bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/mutation/mutation-history.ndjson" ]
  [ -f "${FIXTURE_ROOT}/artifacts/mutation/mutation-trend.json" ]
}

@test "ci mode fails when mutmut runtime is incompatible" {
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "--version" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "run" ]; then
  exit 2
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "export-cicd-stats" ]; then
  exit 2
fi
if [ "${1:-}" = "-" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
  shift 2
  exec "$@"
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"
  run env CI=true MUTATION_USE_SUBPROCESS=false bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CI strict mode"* ]]
}

@test "local mode records incompatibility as skip" {
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "--version" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "run" ]; then
  exit 2
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "export-cicd-stats" ]; then
  exit 2
fi
if [ "${1:-}" = "-" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
  shift 2
  exec "$@"
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"
  run env MUTATION_USE_SUBPROCESS=false bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP: Mutation testing skipped"* ]]
}

@test "survivor budget gate fails when survived exceeds budget" {
  run env MUTATION_SURVIVOR_BUDGET=0 bash "${FIXTURE_ROOT}/t09_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Survived mutants 5 exceed survivor budget 0"* ]]
}
