#!/usr/bin/env bats

# Requirement test-case tags for requirements/16_run_dast-requirements.md
# #R025-T02: Traceability anchor.

# Traceability numbered tags for requirements/16_run_dast-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.

load "helpers/common.bash"

write_dast_13_stub() {
  local root="$1"
  cat > "${root}/14_run_classification_api.py" <<'PYS'
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
PYS
  chmod +x "${root}/14_run_classification_api.py"
}

copy_dast_project_files() {
  create_repo_fixture
  copy_script_to_fixture "16_run_dast.sh"
  write_dast_13_stub "${FIXTURE_ROOT}"
  stub_cmd 1psa "echo write-token"
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

stub_curl_success() {
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
if [[ "$url" == *"/health"* ]]; then
  printf '%s' '{"ok":true}'
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/curl"
}

stub_curl_health_and_zap_alerts() {
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
if [[ "$url" == *"/health"* ]]; then
  printf '%s' '{"ok":true}'
  exit 0
fi
if [[ "$url" == *"/JSON/core/view/version/"* ]]; then
  printf '%s' '{"version":"2.16.1"}'
  exit 0
fi
if [[ "$url" == *"/JSON/core/view/alerts/"* ]]; then
  printf '%s' '{"alerts":[]}'
  exit 0
fi
if [[ "$url" == *"/OTHER/core/other/htmlreport/"* ]]; then
  printf '%s' '<html><body>zap report</body></html>'
  exit 0
fi
printf '%s' '{}'
exit 0
EOF
  chmod +x "${STUB_BIN}/curl"
}

stub_zap_cli_ok() {
  local target="$1"
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
echo "zap $*" >> "${CALLS_LOG}"
echo "zap-stub"
exit 0
EOF
  chmod +x "$target"
}

teardown() {
  teardown_shell_test
}

@test "prints DAST startup banner" {
  #R001
  setup_shell_test
  copy_dast_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/16_run_dast.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running DAST (Dynamic Application Security Testing)"* ]]
}

@test "runs DAST lane when scanner integrations are disabled" {
  #R005 #R010 #R015 #R020
  setup_shell_test
  copy_dast_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=false RUN_MACOS_UI_DAST=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/16_run_dast.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running DAST (Dynamic Application Security Testing)"* ]]
  [[ "$output" == *"Dynamic Application Security Testing (DAST) checks completed."* ]]
}

@test "macOS UI DAST auto-selects proxy port when requested port is occupied" {
  #R025
  setup_shell_test
  copy_dast_project_files
  write_macos_ui_regression_stub "${FIXTURE_ROOT}"
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_health_and_zap_alerts
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  local occupied_port=18090
  /usr/bin/python3 -m http.server "$occupied_port" --bind 127.0.0.1 > "${TEST_TMPDIR}/occupied-port.log" 2>&1 &
  local occupied_pid=$!
  sleep 1
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=true RUN_MACOS_UI_DAST=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    ZAP_CLI_CMD="$zap_path" \
    MACOS_UI_DAST_ZAP_PROXY_PORT="$occupied_port" \
    bash "${FIXTURE_ROOT}/16_run_dast.sh"
  kill "$occupied_pid" >/dev/null 2>&1 || true
  wait "$occupied_pid" >/dev/null 2>&1 || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"is already in use; auto-selected"* ]]
  [[ "$output" == *"TELLER_CLASSIFIER_HTTP_PROXY=http://127.0.0.1:18091"* ]]
  local calls
  calls="$(cat "$CALLS_LOG")"
  [[ "$calls" == *"zap -daemon -dir ${FIXTURE_ROOT}/.security-reports/zap-home/daemon -host 127.0.0.1 -port 18091"* ]]
}

@test "macOS UI DAST rejects non-numeric proxy port configuration" {
  #R025
  setup_shell_test
  copy_dast_project_files
  write_macos_ui_regression_stub "${FIXTURE_ROOT}"
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_health_and_zap_alerts
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=true RUN_MACOS_UI_DAST=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    ZAP_CLI_CMD="$zap_path" \
    MACOS_UI_DAST_ZAP_PROXY_PORT="abc" \
    bash "${FIXTURE_ROOT}/16_run_dast.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MACOS_UI_DAST_ZAP_PROXY_PORT must be numeric"* ]]
}

@test "DAST uses isolated ZAP homes for quick scan and daemon lanes" {
  #R030
  setup_shell_test
  copy_dast_project_files
  write_macos_ui_regression_stub "${FIXTURE_ROOT}"
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  stub_curl_health_and_zap_alerts
  local zap_path="${TEST_TMPDIR}/ZAP.sh"
  stub_zap_cli_ok "$zap_path"
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=true RUN_MACOS_UI_DAST=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    ZAP_CLI_CMD="$zap_path" \
    MACOS_UI_DAST_ZAP_PROXY_PORT=18092 \
    bash "${FIXTURE_ROOT}/16_run_dast.sh"
  [ "$status" -eq 0 ]
  local calls
  calls="$(cat "$CALLS_LOG")"
  [[ "$calls" == *"zap -cmd -dir ${FIXTURE_ROOT}/.security-reports/zap-home/quick-scan"* ]]
  [[ "$calls" == *"zap -daemon -dir ${FIXTURE_ROOT}/.security-reports/zap-home/daemon"* ]]
}

@test "DAST script includes explicit ZAP daemon startup diagnostics" {
  #R035
  setup_shell_test
  copy_dast_project_files
  run /usr/bin/python3 - <<'PY' "${FIXTURE_ROOT}/16_run_dast.sh"
import pathlib
import sys

script_path = pathlib.Path(sys.argv[1])
script_text = script_path.read_text(encoding="utf-8")
required_tokens = [
    "OWASP ZAP daemon proxy failed to become ready",
    "print_zap_startup_log_tail",
    "ZAP startup log tail",
]
for token in required_tokens:
    if token not in script_text:
        raise SystemExit(f"missing diagnostic token: {token}")
PY
  [ "$status" -eq 0 ]
}

@test "category integrity gate asserts seed protection invariants" {
  #R025
  setup_shell_test
  copy_dast_project_files
  run /usr/bin/python3 - <<'PY' "${FIXTURE_ROOT}/16_run_dast.sh"
import pathlib
import sys

script_path = pathlib.Path(sys.argv[1])
script_text = script_path.read_text(encoding="utf-8")

required_tokens = [
    "missing_or_unflagged_seed_rows",
    "seed_flag_outside_canonical_range",
    "seed_row_count_drift",
    "orphaned_transaction_category_links",
]
for token in required_tokens:
    if token not in script_text:
        raise SystemExit(f"missing invariant token: {token}")

legacy_tokens = [
    "unexpected_category_ids",
    "missing_canonical_ids",
]
for token in legacy_tokens:
    if token in script_text:
        raise SystemExit(f"legacy invariant token still present: {token}")
PY
  [ "$status" -eq 0 ]
}
