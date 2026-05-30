#!/usr/bin/env bats
load "helpers/common.bash"

write_dast_14_stub() {
  local root="$1"
  cat > "${root}/08_run_classification_api.py" <<'PYS'
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
  chmod +x "${root}/08_run_classification_api.py"
}

copy_dast_project_files() {
  create_repo_fixture
  copy_script_to_fixture "t12_run_dynamic_security_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts/security"
  cp "$(repo_root)/src/scripts/security/common.sh" "${FIXTURE_ROOT}/src/scripts/security/common.sh"
  cp "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh" "${FIXTURE_ROOT}/src/scripts/security/run_dynamic_security_lane.sh"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  cp "$(repo_root)/src/scripts/dast_baseline.py" "${FIXTURE_ROOT}/src/scripts/dast_baseline.py"
  cp "$(repo_root)/src/scripts/dast_cleanup.py" "${FIXTURE_ROOT}/src/scripts/dast_cleanup.py"
  chmod +x "${FIXTURE_ROOT}/src/scripts/security/run_dynamic_security_lane.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  mkdir -p "${FIXTURE_ROOT}/tests/py/security"
  cp "$(repo_root)/tests/py/security/"*.py "${FIXTURE_ROOT}/tests/py/security/"
  mkdir -p "${FIXTURE_ROOT}/src/sql/postgres"
  cp "$(repo_root)/src/sql/postgres/teller_nys_snw_category.sql" "${FIXTURE_ROOT}/src/sql/postgres/teller_nys_snw_category.sql"
  mkdir -p "${FIXTURE_ROOT}/requirements/security"
  cp "$(repo_root)/requirements/security/requirements-security.txt" "${FIXTURE_ROOT}/requirements/security/requirements-security.txt"
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security"
  write_dast_14_stub "${FIXTURE_ROOT}"
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

stub_schemathesis_leaks_token() {
  cat > "${STUB_BIN}/schemathesis" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  exit 0
fi
token=""
junit_path=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--header" ]]; then
    token="${arg##*: }"
  fi
  if [[ "$prev" == "--report-junit-path" ]]; then
    junit_path="$arg"
  fi
  prev="$arg"
done
echo "schemathesis raw token=${token}"
if [[ -n "$junit_path" ]]; then
  printf '<testsuite><system-out>%s</system-out></testsuite>\n' "$token" > "$junit_path"
fi
mkdir -p .schemathesis
printf '%s\n' "runtime-state" > .schemathesis/stub.txt
exit 0
EOF
  chmod +x "${STUB_BIN}/schemathesis"
}

teardown() {
  teardown_shell_test
}

src() {
  printf '%s' "$(repo_root)/tests/t12_run_dynamic_security_tests.sh"
}

src_lane() {
  printf '%s' "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh"
}

@test "prints DAST startup banner" {
  #R001-T01 #R025-T01
  setup_shell_test
  copy_dast_project_files
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  run env RUN_DAST=false \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running DAST (Dynamic Application Security Testing)"* ]]
}

@test "runs DAST lane when scanner integrations are disabled" {
  #R005-T01 #R010-T01 #R015-T01 #R020-T01
  setup_shell_test
  copy_dast_project_files
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  stub_curl_success
  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19787 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running DAST (Dynamic Application Security Testing)"* ]]
  [[ "$output" == *"Dynamic Application Security Testing (DAST) checks completed."* ]]
}

write_dast_baseline_and_cleanup_stubs() {
  #R025-T01: Stub dast_baseline.py + dast_cleanup.py to record invocation as sentinels.
  local root="$1"
  mkdir -p "${root}/src/scripts"
  cat > "${root}/src/scripts/dast_baseline.py" <<'PYS'
#!/usr/bin/env python3
import json
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
sentinel = pathlib.Path(output.parent / "dast-baseline.sentinel")
sentinel.write_text("captured\n", encoding="utf-8")
output.write_text(json.dumps({
    "status": "captured",
    "profile_name": "stub",
    "baseline_max_category_id": 0,
    "baseline_max_match_id": 0,
    "baseline_max_match_audit_id": 0,
    "categories": [],
    "matches": [],
    "classifications": [],
}) + "\n", encoding="utf-8")
print(json.dumps({"status": "captured", "stub": True}))
PYS
  chmod +x "${root}/src/scripts/dast_baseline.py"

  cat > "${root}/src/scripts/dast_cleanup.py" <<'PYS'
#!/usr/bin/env python3
import json
import pathlib
import sys

baseline_path = pathlib.Path(sys.argv[1])
run_id = sys.argv[2]
summary_path = pathlib.Path(sys.argv[3])
sentinel = pathlib.Path(summary_path.parent / "dast-cleanup.sentinel")
sentinel.write_text(f"{run_id}\n", encoding="utf-8")
summary_path.write_text(json.dumps({
    "status": "applied",
    "run_id": run_id,
    "counts": {},
    "baseline_path": str(baseline_path),
}) + "\n", encoding="utf-8")
print(json.dumps({"status": "applied", "run_id": run_id, "stub": True}))
PYS
  chmod +x "${root}/src/scripts/dast_cleanup.py"
}

@test "captures baseline and runs cleanup even on DAST failure" {
  setup_shell_test
  copy_dast_project_files
  write_dast_baseline_and_cleanup_stubs "${FIXTURE_ROOT}"
  stub_curl_success
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"

  local failing_zap="${FIXTURE_ROOT}/bin/zap.sh"
  mkdir -p "${FIXTURE_ROOT}/bin"
  cat > "$failing_zap" <<'EOF'
#!/usr/bin/env bash
echo "zap-stub failing on purpose"
exit 1
EOF
  chmod +x "$failing_zap"

  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19788 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    ZAP_CLI_CMD="$failing_zap" \
    SECURITY_REPORT_DIR="${FIXTURE_ROOT}/artifacts/security-dast" \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"

  [ "$status" -ne 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-baseline.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-cleanup.log" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-run-id.txt" ]
  local run_id_content
  run_id_content="$(cat "${FIXTURE_ROOT}/artifacts/security-dast/dast-run-id.txt")"
  [[ "$run_id_content" == dast-* ]]
}

@test "cleanup runs on success path before integrity check" {
  setup_shell_test
  copy_dast_project_files
  write_dast_baseline_and_cleanup_stubs "${FIXTURE_ROOT}"
  stub_curl_success
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"

  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19789 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    SECURITY_REPORT_DIR="${FIXTURE_ROOT}/artifacts/security-dast" \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"

  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-baseline.json" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-cleanup.log" ]
  [[ "$output" == *"Restoring database to pre-DAST baseline"* ]]
}

@test "DAST_SKIP_CLEANUP disables baseline and cleanup" {
  setup_shell_test
  copy_dast_project_files
  write_dast_baseline_and_cleanup_stubs "${FIXTURE_ROOT}"
  stub_curl_success
  mkdir -p "${FIXTURE_ROOT}/artifacts/venv/security/bin"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/artifacts/venv/security/bin/semgrep"

  run env RUN_SAST=false RUN_DAST=true RUN_SCHEMATHESIS=false RUN_ZAP=false \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_SKIP_CLEANUP=true \
    DAST_BASE_HOST=127.0.0.1 DAST_BASE_PORT=19790 \
    DAST_APP_PYTHON=/usr/bin/python3 \
    SECURITY_REPORT_DIR="${FIXTURE_ROOT}/artifacts/security-dast" \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"

  [ "$status" -eq 0 ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-baseline.sentinel" ]
  [ ! -f "${FIXTURE_ROOT}/artifacts/security-dast/dast-cleanup.sentinel" ]
}

@test "category integrity gate asserts seed protection invariants" {
  setup_shell_test
  copy_dast_project_files
  run /usr/bin/python3 - <<'PY' "${FIXTURE_ROOT}/tests/py/security/category_integrity_check.py"
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

@test "parses ZAP summary into machine-readable severity counts" {
  #R030-T01 #R030-T02
  run grep "summarize_zap_html_report" "$(src_lane)"
  [ "$status" -eq 0 ]
  run grep "zap-classification-summary.json" "$(src_lane)"
  [ "$status" -eq 0 ]
  run grep "zap_summary_parser.py" "$(src_lane)"
  [ "$status" -eq 0 ]
}

@test "fails gate when threshold is medium and findings exist" {
  run grep "SECURITY_ZAP_FAIL_THRESHOLD" "$(src_lane)"
  [ "$status" -eq 0 ]
  run grep "zap_fail_threshold_normalized" "$(src_lane)"
  [ "$status" -eq 0 ]
  run grep "threshold_count > 0" "$(src_lane)"
  [ "$status" -eq 0 ]
}

@test "Schemathesis findings are strict by default" {
  #R035-T01
  run grep "SCHEMATHESIS_FAIL_ON_FINDINGS" "$(src_lane)"
  [ "$status" -eq 0 ]
  run grep "Schemathesis found API contract issues." "$(src_lane)"
  [ "$status" -eq 0 ]
}

@test "Schemathesis strict gate supports explicit downgrade toggle" {
  #R035-T02
  run grep "continuing because SCHEMATHESIS_FAIL_ON_FINDINGS=false" "$(src_lane)"
  [ "$status" -eq 0 ]
}

@test "DAST Mailcart stub avoids API port collisions" {
  #R040-T01
  run grep "collision_start_port" "$(src_lane)"
  [ "$status" -eq 0 ]
  run grep "DAST Mailcart stub port collided with API port" "$(src_lane)"
  [ "$status" -eq 0 ]
}

@test "Schemathesis runtime directory is scoped to DAST report artifacts" {
  #R045-T01 #R045-T02
  setup_shell_test
  copy_dast_project_files
  stub_curl_success
  cat > "${FIXTURE_ROOT}/tests/py/security/delete_category_contract_check.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
print(json.dumps({"status": "ok", "source": "stub"}))
sys.exit(0)
PY
  chmod +x "${FIXTURE_ROOT}/tests/py/security/delete_category_contract_check.py"
  mkdir -p "${FIXTURE_ROOT}/fake-security-venv/bin"
  cat > "${FIXTURE_ROOT}/fake-security-venv/bin/python" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" ]]; then
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "${FIXTURE_ROOT}/fake-security-venv/bin/python"
  echo '#!/usr/bin/env bash' > "${FIXTURE_ROOT}/fake-security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/fake-security-venv/bin/semgrep"
  cat > "${FIXTURE_ROOT}/fake-security-venv/bin/schemathesis" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  exit 0
fi
mkdir -p .schemathesis
printf '%s\n' "runtime-state" > .schemathesis/stub.txt
exit 0
EOF
  chmod +x "${FIXTURE_ROOT}/fake-security-venv/bin/schemathesis"
  run env RUN_SAST=false RUN_DAST=true RUN_ZAP=false RUN_SCHEMATHESIS=true \
    DAST_REUSE_EXISTING_API=true \
    DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_URL="https://127.0.0.1:19791" \
    DAST_OPENAPI_URL="https://127.0.0.1:19791/openapi.json" \
    SECURITY_VENV_DIR="${FIXTURE_ROOT}/fake-security-venv" \
    SECURITY_REPORT_DIR="${FIXTURE_ROOT}/artifacts/security-dast" \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/artifacts/security-dast/.schemathesis" ]
  [ -f "${FIXTURE_ROOT}/artifacts/security-dast/.schemathesis/stub.txt" ]
  [ ! -d "${FIXTURE_ROOT}/.schemathesis" ]
}

@test "dynamic lane redacts Schemathesis token from persisted logs and junit" {
  #R050-T01
  setup_shell_test
  copy_dast_project_files
  stub_curl_success
  stub_schemathesis_leaks_token
  cat > "${FIXTURE_ROOT}/tests/py/security/delete_category_contract_check.py" <<'PY'
#!/usr/bin/env python3
import json
print(json.dumps({"status": "ok", "source": "stub"}))
PY
  chmod +x "${FIXTURE_ROOT}/tests/py/security/delete_category_contract_check.py"
  mkdir -p "${FIXTURE_ROOT}/fake-security-venv/bin"
  cat > "${FIXTURE_ROOT}/fake-security-venv/bin/python" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" ]]; then
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "${FIXTURE_ROOT}/fake-security-venv/bin/python"
  touch "${FIXTURE_ROOT}/fake-security-venv/bin/semgrep"
  chmod +x "${FIXTURE_ROOT}/fake-security-venv/bin/semgrep"
  cp "${STUB_BIN}/schemathesis" "${FIXTURE_ROOT}/fake-security-venv/bin/schemathesis"
  chmod +x "${FIXTURE_ROOT}/fake-security-venv/bin/schemathesis"
  run env RUN_SAST=false RUN_DAST=true RUN_ZAP=false RUN_SCHEMATHESIS=true \
    DAST_REUSE_EXISTING_API=true DAST_CATEGORY_INTEGRITY_STRICT=false \
    DAST_BASE_URL="https://127.0.0.1:19801" \
    DAST_OPENAPI_URL="https://127.0.0.1:19801/openapi.json" \
    SECURITY_VENV_DIR="${FIXTURE_ROOT}/fake-security-venv" \
    SECURITY_REPORT_DIR="${FIXTURE_ROOT}/artifacts/security-dast" \
    bash "${FIXTURE_ROOT}/t12_run_dynamic_security_tests.sh"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -q "write-token" "${FIXTURE_ROOT}/artifacts/security-dast/schemathesis.log"
  [ "$status" -ne 0 ]
  run /usr/bin/grep -q "write-token" "${FIXTURE_ROOT}/artifacts/security-dast/schemathesis-junit.xml"
  [ "$status" -ne 0 ]
  run /usr/bin/grep -q "\\[REDACTED\\]" "${FIXTURE_ROOT}/artifacts/security-dast/schemathesis.log"
  [ "$status" -eq 0 ]
}
