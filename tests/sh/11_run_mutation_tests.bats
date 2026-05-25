#!/usr/bin/env bats

# Requirement test-case tags for requirements/11_run_mutation_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "11_run_mutation_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin" "${FIXTURE_ROOT}/scripts" "${FIXTURE_ROOT}/tests/py"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "--version" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "pytest" ]; then
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "run" ]; then
  mkdir -p mutants
  cat > mutants/mutmut-cicd-stats.json <<'JSON'
{"killed":90,"survived":10,"total":100}
JSON
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "mutmut" ] && [ "${3:-}" = "export-cicd-stats" ]; then
  mkdir -p mutants
  cat > mutants/mutmut-cicd-stats.json <<'JSON'
{"killed":90,"survived":10,"total":100}
JSON
  exit 0
fi
if [ "${1:-}" = "-" ] && [ -f "${2:-}" ]; then
  stats_path="${2:-}"
  summary_path="${3:-}"
  if [ -n "${summary_path}" ]; then
    cat > "${summary_path}" <<'JSON'
{"total":100,"killed":90,"survived":10,"score":90.0,"mutator_coverage":100.0,"threshold":90,"coverage_threshold":70,"gate_failed":false,"by_module":{}}
JSON
  fi
  [ -f "${stats_path}" ] || cat > "${stats_path}" <<'JSON'
{"killed":90,"survived":10,"total":100}
JSON
  echo "✅ PASS: Mutation score 90.00% (threshold 90.0%), mutator coverage 100.00% (threshold 70.0%)."
  exit 0
fi
if [ "${1:-}" = "-" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
  shift 2
  exec "$@"
fi
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"
  cat > "${FIXTURE_ROOT}/scripts/mutmut_darwin.py" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/scripts/mutmut_darwin.py"
  cat > "${FIXTURE_ROOT}/scripts/mutmut_darwin_stub.py" <<'EOF'
# stub
EOF
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001-T01
  run bash -c "cd '${TEST_TMPDIR}' && '${FIXTURE_ROOT}/11_run_mutation_tests.sh'"
  [ "$status" -eq 0 ]
}

@test "fails when teller-venv python is unavailable" {
  #R005-T01
  rm -rf "${FIXTURE_ROOT}/teller-venv"
  run bash "${FIXTURE_ROOT}/11_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"teller-venv python is required"* ]]
}

@test "preflight failure points to python unit lane" {
  #R010-T01
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
  run env MUTATION_SKIP_PREFLIGHT=false bash "${FIXTURE_ROOT}/11_run_mutation_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"./10_run_python_unit_tests.sh"* ]]
}

@test "writes mutation summary and stats on success" {
  #R015-T01
  run bash "${FIXTURE_ROOT}/11_run_mutation_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/mutation-summary.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/mutmut-cicd-stats.json" ]
}
