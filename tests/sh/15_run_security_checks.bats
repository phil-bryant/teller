#!/usr/bin/env bats

load "helpers/common.bash"

# Minimal OpenAPI/health server for DAST (stdlib only, no Teller/FastAPI deps).
write_dast_13_stub() {
  local root="$1"
  cat > "${root}/14_run_classification_api.py" <<'PY'
#!/usr/bin/env python3
import http.server
import os
import socketserver

host = os.environ.get("TELLER_CLASSIFIER_API_HOST", "127.0.0.1")
port = int(os.environ.get("TELLER_CLASSIFIER_API_PORT", "8787"))


class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
    self.send_response(200)
    self.end_headers()
    if "openapi" in (self.path or ""):
      self.wfile.write(b'{"openapi":"3.0.0","paths":{}}')
    else:
      self.wfile.write(b"ok")

  def log_message(self, *_args):
    return


if __name__ == "__main__":
  with socketserver.TCPServer((host, port), H) as s:
    s.serve_forever()
PY
  chmod +x "${root}/14_run_classification_api.py"
}

# Delegates to system Python3 except for a fake "python3 -m venv" (R005).
write_python3_venv_stub() {
  cat > "${STUB_BIN}/python3" <<'EOS'
#!/usr/bin/env bash
echo "python3 $*" >> "${CALLS_LOG}"
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  vpath="${3:?}"
  mkdir -p "$vpath/bin"
  {
    echo "#!/bin/bash"
    echo "echo semgrep; exit 0"
  } > "$vpath/bin/semgrep"
  chmod +x "$vpath/bin/semgrep"
  {
    echo "#!/bin/bash"
    echo "echo pip; exit 0"
  } > "$vpath/bin/pip"
  chmod +x "$vpath/bin/pip"
  exit 0
fi
exec /usr/bin/python3 "$@"
EOS
  chmod +x "${STUB_BIN}/python3"
}

copy_security_project_files() {
  create_repo_fixture
  copy_script_to_fixture "15_run_security_checks.sh"
  cp "$(repo_root)/requirements-security.txt" "${FIXTURE_ROOT}/"
  cp "$(repo_root)/.semgrep.yml" "${FIXTURE_ROOT}/"
  cp "$(repo_root)/.bandit" "${FIXTURE_ROOT}/"
  mkdir -p "${FIXTURE_ROOT}/teller"
  echo 'x = 1' > "${FIXTURE_ROOT}/teller/safe_test.py"
  write_dast_13_stub "${FIXTURE_ROOT}"
}

install_passing_sast_stubs_in_venv() {
  local vbin="${FIXTURE_ROOT}/.security-venv/bin"
  mkdir -p "$vbin"
  cat > "${vbin}/semgrep" <<'EOF'
#!/usr/bin/env bash
out=""
set -- "$@"
while [ $# -gt 0 ]; do
  if [[ "$1" == -o || "$1" == --output ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"results":[]}' > "$out"
exit 0
EOF
  chmod +x "${vbin}/semgrep"
  cat > "${vbin}/bandit" <<'EOF'
#!/usr/bin/env bash
out=""
set -- "$@"
while [ $# -gt 0 ]; do
  if [[ "$1" == -o ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"results":[]}' > "$out"
exit 0
EOF
  chmod +x "${vbin}/bandit"
  cat > "${vbin}/pip-audit" <<'EOF'
#!/usr/bin/env bash
out=""
set -- "$@"
while [ $# -gt 0 ]; do
  if [[ "$1" == --output ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '[]' > "$out"
exit 0
EOF
  chmod +x "${vbin}/pip-audit"
  cat > "${vbin}/detect-secrets" <<'EOF'
#!/usr/bin/env bash
echo '{"results":{}}'
exit 0
EOF
  chmod +x "${vbin}/detect-secrets"
}

install_sast_gate_fail_semgrep() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/semgrep" <<'EOF'
#!/usr/bin/env bash
out=""
set -- "$@"
while [ $# -gt 0 ]; do
  if [[ "$1" == -o || "$1" == --output ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"results":[{"check_id":"r","path":"f.py","start":{"line":1},"end":{"line":1},"extra":{"message":"e","severity":"ERROR"}}]}' > "$out"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
}

install_bandit_exit_2() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/bandit" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/bandit"
}

install_pip_audit_exit_2() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/pip-audit" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/pip-audit"
}

stub_curl_success() {
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_BIN}/curl"
}

stub_schemathesis_ok() {
  cat > "${STUB_BIN}/schemathesis" <<'EOF'
#!/usr/bin/env bash
# invoked as: schemathesis run URL ...
printf '%s\n' "ok"
exit 0
EOF
  chmod +x "${STUB_BIN}/schemathesis"
}

stub_zap_cli_ok() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
echo "zap-stub" 
exit 0
EOF
  chmod +x "$path"
}

teardown() {
  teardown_shell_test
}

@test "runs with cwd outside repo; paths resolve to script root" {
  #R001
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/bin/bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  mkdir -p "${TEST_TMPDIR}/elsewhere"
  run env RUN_SAST=false RUN_DAST=false \
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && exec bash '${FIXTURE_ROOT}/15_run_security_checks.sh'"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/.security-reports" ]
  [[ "$output" == *"Security checks completed"* ]]
}

write_python3_venv_stub_no_sast_tools() {
  cat > "${STUB_BIN}/python3" <<'EOS'
#!/usr/bin/env bash
echo "python3 $*" >> "${CALLS_LOG}"
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  vpath="${3:?}"
  mkdir -p "$vpath/bin"
  cat > "$vpath/bin/pip" <<'PIP'
#!/usr/bin/env bash
echo "pip $*" >> "${CALLS_LOG}"
exit 0
PIP
  chmod +x "$vpath/bin/pip"
  exit 0
fi
exec /usr/bin/python3 "$@"
EOS
  chmod +x "${STUB_BIN}/python3"
}

@test "bootstraps security venv when missing and does not run pip when semgrep is present" {
  #R005
  setup_shell_test
  copy_security_project_files
  write_python3_venv_stub
  run env RUN_SAST=false RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Creating isolated security virtualenv"* ]]
  [ -d "${FIXTURE_ROOT}/.security-venv" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python3 -m venv ./.security-venv"* ]]
  [[ "$output" != *"Installing security toolchain into"* ]]
}

@test "installs security toolchain in venv when semgrep is absent" {
  #R005
  setup_shell_test
  copy_security_project_files
  write_python3_venv_stub_no_sast_tools
  run env RUN_SAST=false RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing security toolchain into ./.security-venv"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"pip install -r requirements-security.txt"* ]]
}

@test "sets pip-audit to project venv when teller-venv is present" {
  #R010
  setup_shell_test
  copy_security_project_files
  /usr/bin/python3 -m venv "${FIXTURE_ROOT}/teller-venv"
  install_passing_sast_stubs_in_venv
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pip-audit target interpreter:"*teller-venv* ]]
}

@test "lanes off: creates report directory and exits without scanners" {
  #R015
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  run env RUN_SAST=false RUN_DAST=false SECURITY_REPORT_DIR="${FIXTURE_ROOT}/.custom-rep" \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/.custom-rep" ]
}

@test "SAST produces JSON reports and sast summary" {
  #R020
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  for f in semgrep.json bandit.json "pip-audit.json" "detect-secrets.json" sast-summary.json; do
    [ -f "${FIXTURE_ROOT}/.security-reports/${f}" ]
  done
  [[ "$output" == *"SAST summary"* ]]
}

@test "bandit exit code 2 is an execution failure" {
  #R025
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  install_bandit_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Bandit failed to execute."* ]]
}

@test "pip-audit exit code 2 is an execution failure" {
  #R025
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  install_pip_audit_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pip-audit failed to execute."* ]]
}

@test "SAST gate fails on high or critical per summary" {
  #R030
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  install_sast_gate_fail_semgrep
  run env RUN_DAST=false SECURITY_FAIL_ON_HIGH_CRITICAL=true \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SAST gate failed"* ]]
}

@test "DAST starts API, waits for health, completes when DAST tools minimal" {
  #R035
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_SCHEMATHESIS=false RUN_ZAP=false \
    TELLER_CLASSIFIER_API_HOST=127.0.0.1 TELLER_CLASSIFIER_API_PORT=8787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting local classification API for DAST"* ]]
  [ -f "${FIXTURE_ROOT}/.security-reports/classification-api.log" ]
  [[ "$output" == *"DAST checks completed."* ]]
}

@test "token-capture DAST auto skips when application id is absent" {
  #R040
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_SCHEMATHESIS=false RUN_ZAP=false \
    RUN_TOKEN_CAPTURE_DAST=auto \
    TELLER_CLASSIFIER_API_HOST=127.0.0.1 TELLER_CLASSIFIER_API_PORT=8787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Token capture DAST skipped"* ]]
}

@test "DAST fails with clear error when ZAP is enabled but ZAP CLI missing" {
  #R045
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_SCHEMATHESIS=false \
    ZAP_CLI_CMD="/no/such/zap" \
    TELLER_CLASSIFIER_API_HOST=127.0.0.1 TELLER_CLASSIFIER_API_PORT=8787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing ZAP CLI executable:"* ]]
}

@test "DAST with ZAP stub writes zap log and completes" {
  #R045
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  stub_schemathesis_ok
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  run env RUN_SAST=false \
    ZAP_CLI_CMD="$zap_path" \
    TELLER_CLASSIFIER_API_HOST=127.0.0.1 TELLER_CLASSIFIER_API_PORT=8787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    DAST_OPENAPI_URL="http://127.0.0.1:8787/openapi.json" \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/zap-classification.log" ]
  [[ "$output" == *"DAST checks completed."* ]]
}

@test "prints completion line with report directory" {
  #R050
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  run env RUN_SAST=false RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Security checks completed. Reports:"*".security-reports"* ]]
}
