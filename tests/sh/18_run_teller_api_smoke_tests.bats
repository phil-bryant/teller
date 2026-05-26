#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "18_run_teller_api_smoke_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
}

teardown() {
  teardown_shell_test
}

@test "runs from repo root and writes smoke artifacts" {
  #R001-T01 #R005-T01 #R005-T02 #R010-T01 #R010-T02
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
  cat > "${FIXTURE_ROOT}/src/scripts/check_teller_api_drift.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${TEST_TMPDIR}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' '${FIXTURE_ROOT}/18_run_teller_api_smoke_tests.sh'"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/teller-api-smoke.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security/teller-api-smoke.txt" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python cwd=${FIXTURE_ROOT} args=./src/scripts/check_teller_api_drift.py"* ]]
  [[ "$calls" == *"--run-all-tokens"* ]]
}

@test "passes institution id to smoke checker when configured" {
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
  cat > "${FIXTURE_ROOT}/src/scripts/check_teller_api_drift.py" <<'EOF'
print("stub")
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${FIXTURE_ROOT}/teller-venv/bin/python' TELLER_SMOKE_INSTITUTION_ID='chase' ./18_run_teller_api_smoke_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--institution-id chase"* ]]
}

@test "fails fast for non-executable explicit interpreter path" {
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON=./missing-python ./18_run_teller_api_smoke_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project python not executable"* ]]
}
