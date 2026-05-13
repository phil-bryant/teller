#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "04_run_dependency_freshness_checks.sh"
  mkdir -p "${FIXTURE_ROOT}/scripts"
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
  cat > "${FIXTURE_ROOT}/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${TEST_TMPDIR}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_CANARY=false '${FIXTURE_ROOT}/04_run_dependency_freshness_checks.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/dependency-freshness.txt" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/postgres-freshness.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./scripts/check_dependency_freshness.py"* ]]
  [[ "$calls" == *"--fail-on-direct-outdated"* ]]
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" == *"--check-server-version --server-psql-args -h localhost -U teller -d prod"* ]]
  [[ "$calls" == *"--check-cves --cve-snapshot ./security/postgres-cve-snapshot.json --cve-policy ./security/postgres-cve-policy.json"* ]]
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
  cat > "${FIXTURE_ROOT}/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_CANARY=false RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=false ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./scripts/check_dependency_freshness.py"* ]]
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
  cat > "${FIXTURE_ROOT}/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_CANARY=false RUN_POSTGRES_FRESHNESS=false DEPENDENCY_FAIL_ON_MAJOR=true ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--fail-on-major"* ]]
}

@test "fails fast for non-executable explicit interpreter path" {
  #R005
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON=./missing-python ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project python not executable"* ]]
}

@test "runs optional Teller drift check when enabled" {
  #R015 #R020
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
  cat > "${FIXTURE_ROOT}/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF
  cat > "${FIXTURE_ROOT}/scripts/check_teller_api_drift.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_CANARY=true ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/teller-api-drift.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/teller-api-drift.txt" ]
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
  cat > "${FIXTURE_ROOT}/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_CANARY=false RUN_POSTGRES_FRESHNESS=false ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/postgres-freshness.json" ]
  [ ! -f "${FIXTURE_ROOT}/.security-reports/postgres-freshness.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"./scripts/check_postgres_freshness.py"* ]]
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
  cat > "${FIXTURE_ROOT}/scripts/check_dependency_freshness.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' RUN_TELLER_CANARY=false POSTGRES_CHECK_CVES=false ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"./scripts/check_postgres_freshness.py"* ]]
  [[ "$calls" != *"--check-cves"* ]]
  [[ "$calls" != *"--cve-snapshot"* ]]
  [[ "$calls" != *"--cve-policy"* ]]
}
