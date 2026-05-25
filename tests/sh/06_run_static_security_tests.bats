#!/usr/bin/env bats

# Requirement test-case tags for requirements/06_run_static_security_tests-requirements.md
# #R015-T02: Traceability anchor.
# #R025-T02: Traceability anchor.
# #R030-T02: Traceability anchor.
# #R090-T02: Traceability anchor.
# #R090-T03: Traceability anchor.
# #R090-T04: Traceability anchor.
# #R090-T05: Traceability anchor.

# Traceability numbered tags for requirements/06_run_static_security_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R040-T01: Traceability anchor.
# #R045-T01: Traceability anchor.
# #R047-T01: Traceability anchor.
# #R050-T01: Traceability anchor.
# #R055-T01: Traceability anchor.
# #R060-T01: Traceability anchor.
# #R065-T01: Traceability anchor.
# #R070-T01: Traceability anchor.
# #R090-T01: Traceability anchor.

load "helpers/common.bash"

# Minimal OpenAPI/health server for DAST (stdlib only, no Teller/FastAPI deps).
write_dast_13_stub() {
  local root="$1"
  cat > "${root}/15_run_classification_api.py" <<'PY'
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
  chmod +x "${root}/15_run_classification_api.py"
}

write_macos_ui_regression_stub() {
  local root="$1"
  cat > "${root}/10_run_macos_ui_regression_tests.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "macos-ui-regression-stub RUN_SNAPSHOT_TESTS=${RUN_SNAPSHOT_TESTS:-unset} RUN_XCUITESTS=${RUN_XCUITESTS:-unset} TELLER_CLASSIFIER_API_URL=${TELLER_CLASSIFIER_API_URL:-unset} TELLER_CLASSIFIER_HTTP_PROXY=${TELLER_CLASSIFIER_HTTP_PROXY:-unset}"
SH
  chmod +x "${root}/10_run_macos_ui_regression_tests.sh"
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
    echo "echo gitleaks; exit 0"
  } > "$vpath/bin/gitleaks"
  chmod +x "$vpath/bin/gitleaks"
  {
    echo "#!/bin/bash"
    echo "echo ruff; exit 0"
  } > "$vpath/bin/ruff"
  chmod +x "$vpath/bin/ruff"
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
  copy_script_to_fixture "06_run_static_security_tests.sh"
  cp "$(repo_root)/requirements-security.txt" "${FIXTURE_ROOT}/"
  cp "$(repo_root)/.semgrep.yml" "${FIXTURE_ROOT}/"
  cp "$(repo_root)/.bandit" "${FIXTURE_ROOT}/"
  mkdir -p "${FIXTURE_ROOT}/teller"
  echo 'x = 1' > "${FIXTURE_ROOT}/teller/safe_test.py"
  write_dast_13_stub "${FIXTURE_ROOT}"
  write_macos_ui_regression_stub "${FIXTURE_ROOT}"
  stub_cmd 1psa "echo write-token"
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
echo "detect-secrets $*" >> "${CALLS_LOG}"
echo '{"results":{}}'
exit 0
EOF
  chmod +x "${vbin}/detect-secrets"
  cat > "${vbin}/ruff" <<'EOF'
#!/usr/bin/env bash
printf '%s' '[]'
exit 0
EOF
  chmod +x "${vbin}/ruff"
  cat > "${vbin}/gitleaks" <<'EOF'
#!/usr/bin/env bash
echo "gitleaks $*" >> "${CALLS_LOG}"
report=""
set -- "$@"
while [ $# -gt 0 ]; do
  if [[ "$1" == --report-path ]]; then
    report="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '[]' > "$report"
exit 0
EOF
  chmod +x "${vbin}/gitleaks"
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

install_sast_gate_fail_semgrep_warning() {
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
printf '%s' '{"results":[{"check_id":"r-warning","path":"f.py","start":{"line":7},"end":{"line":7},"extra":{"message":"warning finding","severity":"WARNING"}}]}' > "$out"
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
}

install_bandit_medium_finding() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/bandit" <<'EOF'
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
printf '%s' '{"results":[{"issue_severity":"MEDIUM","issue_text":"medium risk call"}]}' > "$out"
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/bandit"
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

install_pip_audit_vulnerability() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/pip-audit" <<'EOF'
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
printf '%s' '[{"name":"example-pkg","version":"1.0.0","vulns":[{"id":"PYSEC-2026-001","fix_versions":["1.0.1"]}]}]' > "$out"
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/pip-audit"
}

install_ruff_exit_2() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/ruff" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/ruff"
}

install_ruff_findings() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/ruff" <<'EOF'
#!/usr/bin/env bash
printf '%s' '[{"code":"F401","filename":"./teller/safe_test.py","location":{"row":1,"column":1},"message":"unused import"}]'
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/ruff"
}

install_gitleaks_exit_2() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/gitleaks"
}

install_gitleaks_findings() {
  cat > "${FIXTURE_ROOT}/.security-venv/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
report=""
set -- "$@"
while [ $# -gt 0 ]; do
  if [[ "$1" == --report-path ]]; then
    report="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '[{"Description":"Hardcoded secret","File":"./teller/safe_test.py"}]' > "$report"
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/gitleaks"
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
echo "schemathesis $*" >> "${CALLS_LOG}"
printf '%s\n' "ok"
exit 0
EOF
  chmod +x "${STUB_BIN}/schemathesis"
}

stub_schemathesis_findings() {
  cat > "${STUB_BIN}/schemathesis" <<'EOF'
#!/usr/bin/env bash
echo "schemathesis $*" >> "${CALLS_LOG}"
printf '%s\n' "contract-findings"
exit 1
EOF
  chmod +x "${STUB_BIN}/schemathesis"
}

stub_zap_cli_ok() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
echo "zap $*" >> "${CALLS_LOG}"
echo "zap-stub" 
exit 0
EOF
  chmod +x "$path"
}

stub_swiftlint_ok() {
  cat > "${STUB_BIN}/swiftlint" <<'EOF'
#!/usr/bin/env bash
echo "swiftlint $*" >> "${CALLS_LOG}"
printf '%s' '[]'
exit 0
EOF
  chmod +x "${STUB_BIN}/swiftlint"
}

stub_swiftlint_warning() {
  cat > "${STUB_BIN}/swiftlint" <<'EOF'
#!/usr/bin/env bash
echo "swiftlint $*" >> "${CALLS_LOG}"
printf '%s' '[{"rule_id":"force_unwrapping","severity":"Warning","reason":"force unwrap in security-sensitive code"}]'
exit 0
EOF
  chmod +x "${STUB_BIN}/swiftlint"
}

stub_swiftlint_exit_2() {
  cat > "${STUB_BIN}/swiftlint" <<'EOF'
#!/usr/bin/env bash
echo "swiftlint $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/swiftlint"
}

stub_shellcheck_clean() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "shellcheck $*" >> "${CALLS_LOG}"
printf '%s' '[]'
exit 0
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

stub_shellcheck_error_findings() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "shellcheck $*" >> "${CALLS_LOG}"
printf '%s' '[{"file":"./06_run_static_security_tests.sh","line":1,"level":"error","code":2086,"message":"Double quote to prevent globbing"}]'
exit 1
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

stub_shellcheck_warning_findings() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "shellcheck $*" >> "${CALLS_LOG}"
printf '%s' '[{"file":"./06_run_static_security_tests.sh","line":1,"level":"warning","code":2154,"message":"variable referenced but not assigned"}]'
exit 1
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

stub_shellcheck_exit_2() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "shellcheck $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

stub_clamscan_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
OUT
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_infected() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
./bad.bin: Eicar-Test-Signature FOUND
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 1
OUT
exit 1
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_exit_2() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_slow_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
sleep 2
cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
OUT
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_clamscan_missing_db_then_clean() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/usr/bin/env bash
echo "clamscan $*" >> "${CALLS_LOG}"
state="${TEST_TMPDIR}/clamscan-state"
if [[ ! -f "$state" ]]; then
  cat <<'OUT'
LibClamAV Error: cli_loaddbdir: No supported database files found in /opt/homebrew/var/lib/clamav
ERROR: Can't open file or directory

----------- SCAN SUMMARY -----------
Known viruses: 0
Engine version: 1.0
Scanned files: 0
Infected files: 0
OUT
  : > "$state"
  exit 2
fi
cat <<'OUT'
----------- SCAN SUMMARY -----------
Known viruses: 12345
Engine version: 1.0
Scanned files: 10
Infected files: 0
OUT
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

stub_freshclam_ok() {
  cat > "${STUB_BIN}/freshclam" <<'EOF'
#!/usr/bin/env bash
echo "freshclam $*" >> "${CALLS_LOG}"
echo "Database updated"
exit 0
EOF
  chmod +x "${STUB_BIN}/freshclam"
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
    bash -c "cd '${TEST_TMPDIR}/elsewhere' && exec bash '${FIXTURE_ROOT}/06_run_static_security_tests.sh'"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/.security-reports" ]
  [[ "$output" == *"running SAST (Static Application Security Testing)"* ]]
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
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
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
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
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
  stub_shellcheck_clean
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
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
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/.custom-rep" ]
}

@test "SAST produces JSON reports and sast summary" {
  #R020 #R025 #R030 #R065
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  for f in semgrep.json bandit.json "pip-audit.json" "detect-secrets.json" ruff.json gitleaks.json shellcheck.json swiftlint.json sast-summary.json; do
    [ -f "${FIXTURE_ROOT}/.security-reports/${f}" ]
  done
  ruff_total="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("ruff_total",-1))' "${FIXTURE_ROOT}/.security-reports/sast-summary.json")"
  ruff_high="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("ruff_high_critical",-1))' "${FIXTURE_ROOT}/.security-reports/sast-summary.json")"
  shellcheck_total="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("shellcheck_total",-1))' "${FIXTURE_ROOT}/.security-reports/sast-summary.json")"
  shellcheck_high="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("shellcheck_high_critical",-1))' "${FIXTURE_ROOT}/.security-reports/sast-summary.json")"
  gitleaks_findings="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("gitleaks_findings",-1))' "${FIXTURE_ROOT}/.security-reports/sast-summary.json")"
  [ "$ruff_total" = "0" ]
  [ "$ruff_high" = "0" ]
  [ "$shellcheck_total" = "0" ]
  [ "$shellcheck_high" = "0" ]
  [ "$gitleaks_findings" = "0" ]
  [[ "$output" == *"Static Application Security Testing (SAST) summary"* ]]
  [[ "$output" == *"Static Application Security Testing (SAST) checks completed."* ]]
}

@test "SAST prints boxed tool headers with explainers and official URLs" {
  #R025 #R055 #R065
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+==============================================================================+"* ]]
  [[ "$output" == *"Security Tool: Semgrep"* ]]
  [[ "$output" == *"Static pattern-based scanning for security and correctness issues."* ]]
  [[ "$output" == *"URL: https://semgrep.dev/docs/"* ]]
  [[ "$output" == *"Security Tool: Bandit"* ]]
  [[ "$output" == *"URL: https://bandit.readthedocs.io/"* ]]
  [[ "$output" == *"Security Tool: pip-audit"* ]]
  [[ "$output" == *"URL: https://github.com/pypa/pip-audit"* ]]
  [[ "$output" == *"Security Tool: detect-secrets"* ]]
  [[ "$output" == *"URL: https://github.com/Yelp/detect-secrets"* ]]
  [[ "$output" == *"Security Tool: Ruff"* ]]
  [[ "$output" == *"URL: https://docs.astral.sh/ruff/"* ]]
  [[ "$output" == *"Security Tool: gitleaks"* ]]
  [[ "$output" == *"URL: https://github.com/gitleaks/gitleaks"* ]]
  [[ "$output" == *"Security Tool: ShellCheck"* ]]
  [[ "$output" == *"URL: https://www.shellcheck.net/"* ]]
}

@test "Semgrep prints detailed status when output is unsuppressed" {
  #R045 #R047
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Semgrep detailed status: exit_code=0;"* ]]
  [[ "$output" == *"report=./.security-reports/semgrep.json"* ]]
}

@test "Bandit prints detailed status when output is unsuppressed" {
  #R050
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bandit detailed status: exit_code=0;"* ]]
  [[ "$output" == *"report=./.security-reports/bandit.json"* ]]
}

@test "pip-audit prints detailed status when output is unsuppressed" {
  #R055
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pip-audit detailed status: exit_code=0;"* ]]
  [[ "$output" == *"report=./.security-reports/pip-audit.json"* ]]
}

@test "detect-secrets prints detailed status when output is unsuppressed" {
  #R060
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"detect-secrets detailed status: exit_code=0;"* ]]
  [[ "$output" == *"report=./.security-reports/detect-secrets.json"* ]]
}

@test "Ruff prints detailed status when output is unsuppressed" {
  #R065
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ruff detailed status: exit_code=0;"* ]]
  [[ "$output" == *"report=./.security-reports/ruff.json"* ]]
}

@test "ShellCheck prints detailed status when output is unsuppressed" {
  #R070
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ShellCheck detailed status: exit_code=0;"* ]]
  [[ "$output" == *"report=./.security-reports/shellcheck.json"* ]]
}

@test "detect-secrets scan excludes Ruff cache artifacts" {
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"detect-secrets scan --all-files --force-use-all-plugins --exclude-files"* ]]
  [[ "$calls" == *".ruff_cache/"* ]]
}

@test "gitleaks scans tracked-file snapshot source instead of repo root" {
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  run env RUN_DAST=false RUN_SWIFT_SAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"gitleaks detect --source /"* ]]
  [[ "$calls" != *"gitleaks detect --source . --no-git"* ]]
}

@test "Swift SAST runs SwiftLint when Swift sources are present" {
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier"
  cat > "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier/App.swift" <<'EOF'
import Foundation
EOF
  stub_swiftlint_ok
  run env RUN_DAST=false RUN_SWIFT_SAST=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/swiftlint.json" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"swiftlint lint --quiet --reporter json --force-exclude --only-rule force_cast --only-rule force_try --only-rule force_unwrapping"* ]]
  [[ "$calls" == *"./macos-ui/Sources"* ]]
}

@test "SwiftLint exit code 2 is an execution failure" {
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier"
  cat > "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier/App.swift" <<'EOF'
import Foundation
EOF
  stub_swiftlint_exit_2
  run env RUN_DAST=false RUN_SWIFT_SAST=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SwiftLint failed to execute."* ]]
}

@test "bandit exit code 2 is an execution failure" {
  #R025
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_bandit_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Bandit failed to execute."* ]]
}

@test "pip-audit exit code 2 is an execution failure" {
  #R025
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_pip_audit_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pip-audit failed to execute."* ]]
}

@test "ruff exit code 2 is an execution failure" {
  #R025
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_ruff_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ruff failed to execute."* ]]
}

@test "ruff findings fail SAST gate when medium-or-higher policy is enabled" {
  #R030
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_ruff_findings
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Ruff reported findings"* ]]
  [[ "$output" == *"Static Application Security Testing (SAST) gate failed"* ]]
}

@test "gitleaks exit code 2 is an execution failure" {
  #R075
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_gitleaks_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gitleaks failed to execute."* ]]
}

@test "SAST gate fails on semgrep error findings" {
  #R030
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_sast_gate_fail_semgrep
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Static Application Security Testing (SAST) gate failed"* ]]
}

@test "financial policy blocks Semgrep warning findings" {
  #R090
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_sast_gate_fail_semgrep_warning
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Semgrep findings (1)"* ]]
  [[ "$output" == *"[WARNING] r-warning @ f.py:7"* ]]
  [[ "$output" == *"Medium-or-higher findings detected."* ]]
}

@test "financial policy medium-or-higher gate defaults to enabled" {
  #R090
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_sast_gate_fail_semgrep_warning
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Medium-or-higher findings detected."* ]]
}

@test "financial policy blocks Bandit medium findings" {
  #R090
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_bandit_medium_finding
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Bandit detailed status: exit_code=1; findings=1"* ]]
  [[ "$output" == *"Medium-or-higher findings detected."* ]]
}

@test "financial policy blocks pip-audit vulnerabilities" {
  #R090
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_pip_audit_vulnerability
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pip-audit detailed status: exit_code=1; vulnerabilities=1"* ]]
  [[ "$output" == *"Medium-or-higher findings detected."* ]]
}

@test "gitleaks findings fail SAST gate when medium-or-higher policy is enabled" {
  #R075 #R030
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  install_gitleaks_findings
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gitleaks reported findings"* ]]
  [[ "$output" == *"Static Application Security Testing (SAST) gate failed"* ]]
}

@test "financial policy blocks ShellCheck warning findings" {
  #R090
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_warning_findings
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ShellCheck reported findings"* ]]
  [[ "$output" == *"Medium-or-higher findings detected."* ]]
}

@test "ShellCheck exit code 2 is an execution failure" {
  #R065
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_exit_2
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ShellCheck failed to execute."* ]]
}

@test "ShellCheck error findings fail SAST gate when medium-or-higher policy is enabled" {
  #R065 #R030
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_error_findings
  run env RUN_DAST=false SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ShellCheck reported findings"* ]]
  [[ "$output" == *"Static Application Security Testing (SAST) gate failed"* ]]
}

@test "financial policy blocks SwiftLint warning findings" {
  #R090
  setup_shell_test
  copy_security_project_files
  install_passing_sast_stubs_in_venv
  stub_shellcheck_clean
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier"
  cat > "${FIXTURE_ROOT}/macos-ui/Sources/TransactionClassifier/App.swift" <<'EOF'
import Foundation
EOF
  stub_swiftlint_warning
  run env RUN_DAST=false RUN_SWIFT_SAST=true SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Running SwiftLint (security-focused rules)"* ]]
  [[ "$output" == *"Medium-or-higher findings detected."* ]]
}

@test "DAST starts API, waits for health, completes when DAST tools minimal" {
  #R035 #R070 #R080
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Starting local classification API for Dynamic Application Security Testing (DAST)"* ]]
  [ -f "${FIXTURE_ROOT}/.security-reports/classification-api.log" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/category-integrity.json" ]
  category_integrity_status="$(/usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("status",""))' "${FIXTURE_ROOT}/.security-reports/category-integrity.json")"
  [ "$category_integrity_status" = "error" ]
  [[ "$output" == *"Category integrity report:"* ]]
  [[ "$output" == *"Dynamic Application Security Testing (DAST) checks completed."* ]]
}

@test "token-capture DAST auto skips when application id is absent" {
  #R040
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    RUN_TOKEN_CAPTURE_DAST=auto \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18788 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Token capture Dynamic Application Security Testing (DAST) skipped"* ]]
}

@test "DAST fails with clear error when ZAP is enabled but ZAP CLI missing" {
  #R045
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    ZAP_CLI_CMD="/no/such/zap" \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18789 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing ZAP CLI executable:"* ]]
}

@test "DAST with ZAP stub writes zap log and completes" {
  #R045 #R070
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  stub_schemathesis_ok
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  run env RUN_SAST=false RUN_DAST=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    ZAP_CLI_CMD="$zap_path" \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18791 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    DAST_OPENAPI_URL="http://127.0.0.1:18791/openapi.json" \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/zap-classification.log" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"zap -cmd -dir ${FIXTURE_ROOT}/.security-reports/zap-home"* ]]
  [[ "$calls" != *"--exclude-path /v1/categories"* ]]
  [[ "$calls" != *"--exclude-path /v1/categories/{nys_snw_category_id}"* ]]
  [[ "$output" == *"Dynamic Application Security Testing (DAST) checks completed."* ]]
}

@test "DAST honors custom ZAP_HOME_DIR override" {
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  stub_schemathesis_ok
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  local custom_zap_home="${FIXTURE_ROOT}/.custom-zap-home"
  run env RUN_SAST=false RUN_DAST=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    ZAP_CLI_CMD="$zap_path" \
    ZAP_HOME_DIR="$custom_zap_home" \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18794 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    DAST_OPENAPI_URL="http://127.0.0.1:18794/openapi.json" \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [ -d "$custom_zap_home" ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"zap -cmd -dir ${custom_zap_home}"* ]]
}

@test "DAST enforces ZAP_QUIET=false by omitting ZAP silent flag" {
  #R085
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  stub_schemathesis_ok
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  run env RUN_SAST=false RUN_DAST=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    ZAP_CLI_CMD="$zap_path" \
    ZAP_QUIET=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18795 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    DAST_OPENAPI_URL="http://127.0.0.1:18795/openapi.json" \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"zap -cmd -dir ${FIXTURE_ROOT}/.security-reports/zap-home"* ]]
  [[ "$calls" != *" -silent"* ]]
}

@test "Schemathesis findings do not abort DAST lane" {
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  stub_schemathesis_findings
  run env RUN_SAST=false RUN_DAST=true RUN_ZAP=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=18793 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    DAST_OPENAPI_URL="http://127.0.0.1:18793/openapi.json" \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Schemathesis found API contract issues; continuing to ZAP and Dynamic Application Security Testing (DAST) gating."* ]]
  [[ "$output" == *"Dynamic Application Security Testing (DAST) checks completed."* ]]
}

@test "prints completion line with report directory" {
  #R050
  setup_shell_test
  copy_security_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  touch "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  run env RUN_SAST=false RUN_DAST=false \
    bash "${FIXTURE_ROOT}/06_run_static_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Security checks completed. Reports:"*".security-reports"* ]]
}
