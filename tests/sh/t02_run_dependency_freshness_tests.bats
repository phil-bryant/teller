#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t02_run_dependency_freshness_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
}

teardown() {
  teardown_shell_test
}

@test "runs from repo root and writes freshness artifacts" {
  #R001-T01 #R005-T01 #R005-T02 #R010-T01 #R010-T02 #R010-T03 #R010-T04 #R020-T01 #R025-T01 #R025-T02 #R025-T03
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

  run bash -c "cd '${TEST_TMPDIR}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' '${FIXTURE_ROOT}/t02_run_dependency_freshness_tests.sh'"
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

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./src/scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" != *"--fail-on-direct-outdated"* ]]
}

@test "passes major gating flag when enabled" {
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

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_MAJOR=true ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--fail-on-major"* ]]
}

@test "fails fast for non-executable explicit interpreter path" {
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON=./missing-python ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project python not executable"* ]]
}

@test "skips PostgreSQL freshness lane when disabled" {
  #R020-T02 #R020-T03
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

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_POSTGRES_FRESHNESS=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.json" ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_postgres_freshness.py"* ]]
}

@test "skips Teller API version freshness lane when disabled" {
  #R015-T01 #R015-T02
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

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_VERSION_FRESHNESS=false RUN_POSTGRES_FRESHNESS=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./src/scripts/check_teller_api_version_freshness.py"* ]]
}

@test "prints PostgreSQL server-check target diagnostics for explicit args" {
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

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' POSTGRES_SERVER_PSQL_ARGS='-h dbhost -U teller -d prod' ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PostgreSQL server check target: psql args (explicit)"* ]]
}

@test "omits PostgreSQL CVE args when disabled" {
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

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' POSTGRES_CHECK_CVES=false ./t02_run_dependency_freshness_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./src/scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" != *"--check-cves"* ]]
  [[ "$calls" != *"--cve-snapshot"* ]]
  [[ "$calls" != *"--cve-policy"* ]]
}
