#!/usr/bin/env bats

load "helpers/common.bash"

write_dast_13_stub() {
  local root="$1"
  cat > "${root}/13_run_classification_api.py" <<'PYS'
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
  chmod +x "${root}/13_run_classification_api.py"
}

copy_dast_project_files() {
  create_repo_fixture
  copy_script_to_fixture "15_run_dast.sh"
  write_dast_13_stub "${FIXTURE_ROOT}"
  stub_cmd 1psa "echo write-token"
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

teardown() {
  teardown_shell_test
}

@test "prints DAST startup banner" {
  setup_shell_test
  copy_dast_project_files
  mkdir -p "${FIXTURE_ROOT}/.security-venv/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/.security-venv/bin/semgrep"
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/15_run_dast.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running DAST (Dynamic Application Security Testing)"* ]]
}

@test "runs DAST lane when scanner integrations are disabled" {
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
    bash "${FIXTURE_ROOT}/15_run_dast.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running DAST (Dynamic Application Security Testing)"* ]]
  [[ "$output" == *"Dynamic Application Security Testing (DAST) checks completed."* ]]
}
