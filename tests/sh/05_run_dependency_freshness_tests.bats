#!/usr/bin/env bats

# Requirement test-case tags for requirements/05_run_dependency_freshness_tests-requirements.md
# #R005-T02: Traceability anchor.
# #R010-T02: Traceability anchor.
# #R010-T03: Traceability anchor.
# #R010-T04: Traceability anchor.
# #R015-T02: Traceability anchor.
# #R020-T02: Traceability anchor.
# #R020-T03: Traceability anchor.
# #R025-T02: Traceability anchor.
# #R025-T03: Traceability anchor.

# Traceability numbered tags for requirements/05_run_dependency_freshness_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "05_run_dependency_freshness_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
}

teardown() {
  teardown_shell_test
}

@test "runs from repo root and writes freshness artifacts" {
  #R001 #R005 #R010 #R020 #R025
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${TEST_TMPDIR}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' '${FIXTURE_ROOT}/05_run_dependency_freshness_tests.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/dependency-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/dependency-freshness.txt" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/teller-api-version-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/teller-api-version-freshness.txt" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" == *"--fail-on-direct-outdated"* ]]
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_teller_api_version_freshness.py"* ]]
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" == *"--check-server-version --server-psql-args -h localhost -U teller -d prod"* ]]
  [[ "$calls" == *"--check-cves --cve-snapshot ./config/security/postgres-cve-snapshot.json --cve-policy ./config/security/postgres-cve-policy.json"* ]]
  [[ "$calls" == *"--refresh-cve-snapshot"* ]]
  [[ "$calls" == *"--fail-on-cve"* ]]
}

@test "can disable direct dependency freshness gate" {
  #R010
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=false ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./src/scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" != *"--fail-on-direct-outdated"* ]]
}

@test "passes major gating flag when enabled" {
  #R010
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_MAJOR=true ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--fail-on-major"* ]]
}

@test "fails fast for non-executable explicit interpreter path" {
  #R005
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON=./missing-python ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project python not executable"* ]]
}

@test "skips PostgreSQL freshness lane when disabled" {
  #R020
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.json" ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_postgres_freshness.py"* ]]
}

@test "skips Teller API version freshness lane when disabled" {
  #R015
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_VERSION_FRESHNESS=false RUN_POSTGRES_FRESHNESS=false ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_teller_api_version_freshness.py"* ]]
}

@test "prints PostgreSQL server-check target diagnostics for explicit args" {
  #R020
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' POSTGRES_SERVER_PSQL_ARGS='-h dbhost -U teller -d prod' ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PostgreSQL server check target: psql args (explicit)"* ]]
}

@test "omits PostgreSQL CVE args when disabled" {
  #R025
  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin"
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python" <<EOF
#!/usr/bin/env bash
echo "python args=\$*" >> "${CALLS_LOG}"
out_json=""
out_text=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-json) out_json="\$2"; shift 2 ;;
    --output-text) out_text="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out_json" ]] && echo '{}' > "\$out_json"
[[ -n "\$out_text" ]] && echo 'ok' > "\$out_text"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python"
  cat > "${FIXTURE_ROOT}/src/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' POSTGRES_CHECK_CVES=false ./05_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./src/scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" != *"--check-cves"* ]]
  [[ "$calls" != *"--cve-snapshot"* ]]
  [[ "$calls" != *"--cve-policy"* ]]
}
