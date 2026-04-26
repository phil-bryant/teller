#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_SAST="${RUN_SAST:-true}"
RUN_DAST="${RUN_DAST:-true}"
RUN_SWIFT_SAST="${RUN_SWIFT_SAST:-true}"
#R015: Support configurable execution lanes and report destination.
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./.security-venv}"

mkdir -p "$REPORT_DIR"

#R001: Prefer project venv when available.
if [[ -d "./teller-venv" ]]; then
  # shellcheck disable=SC1091
  source "./teller-venv/bin/activate"
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    echo "Install security tooling with: pip install -r requirements-security.txt"
    exit 1
  fi
}

print_tool_header() {
  #R055: Delimit each security tool execution with a boxed descriptor header.
  local tool_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local tool_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Security Tool: ${tool_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${tool_url}"
  printf '%s\n' "$border"
}

ensure_security_venv() {
  #R005: Bootstrap isolated security toolchain environment before scanning.
  if [[ ! -d "$SECURITY_VENV_DIR" ]]; then
    echo "▶ Creating isolated security virtualenv at ${SECURITY_VENV_DIR}"
    python3 -m venv "$SECURITY_VENV_DIR"
  fi

  local security_pip="${SECURITY_VENV_DIR}/bin/pip"
  local security_semgrep="${SECURITY_VENV_DIR}/bin/semgrep"
  if [[ ! -x "$security_semgrep" ]]; then
    echo "▶ Installing security toolchain into ${SECURITY_VENV_DIR}"
    "$security_pip" install --upgrade pip
    "$security_pip" install -r requirements-security.txt
  fi
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if (( "$(date +%s)" - start_ts >= timeout_seconds )); then
      echo "❌ Timed out waiting for ${url}"
      return 1
    fi
    sleep 1
  done
}

run_zap_quick_scan() {
  local zap_cli_cmd="$1"
  local target_url="$2"
  local html_report="$3"
  local log_report="$4"
  print_tool_header \
    "OWASP ZAP" \
    "Dynamic scan of live HTTP endpoints for common web vulnerabilities." \
    "Uses quick scan mode to spider and actively probe reachable routes." \
    "https://www.zaproxy.org/"
  echo "▶ Running OWASP ZAP quick scan (CLI) against ${target_url}"
  "$zap_cli_cmd" -cmd \
    -quickurl "$target_url" \
    -quickout "$html_report" \
    -quickprogress \
    -silent | tee "$log_report"
}

run_swift_sast() {
  local swift_report="$1"
  local swift_ui_dir="${SWIFT_UI_DIR:-./macos-ui}"
  local swift_targets=()

  if [[ "$RUN_SWIFT_SAST" != "true" ]]; then
    echo "ℹ️  Swift Static Application Security Testing (SAST) skipped (set RUN_SWIFT_SAST=true to enable)."
    printf '[]\n' > "$swift_report"
    return 0
  fi

  if [[ ! -d "$swift_ui_dir" ]]; then
    echo "ℹ️  Swift Static Application Security Testing (SAST) skipped (directory not found: ${swift_ui_dir})."
    printf '[]\n' > "$swift_report"
    return 0
  fi

  for candidate in "${swift_ui_dir}/Sources" "${swift_ui_dir}/Tests" "${swift_ui_dir}/UITests"; do
    if [[ -d "$candidate" ]]; then
      swift_targets+=("$candidate")
    fi
  done

  if [[ "${#swift_targets[@]}" -eq 0 ]]; then
    echo "ℹ️  Swift Static Application Security Testing (SAST) skipped (no Swift source/test directories under ${swift_ui_dir})."
    printf '[]\n' > "$swift_report"
    return 0
  fi

  require_command swiftlint
  print_tool_header \
    "SwiftLint" \
    "Static linting for Swift code quality and risky language usage." \
    "Security lane checks force-cast, force-try, and force-unwrapping patterns." \
    "https://realm.github.io/SwiftLint/"
  echo "▶ Running SwiftLint (security-focused rules) in ${swift_ui_dir}"
  set +e
  swiftlint lint \
    --quiet \
    --reporter json \
    --force-exclude \
    --only-rule force_cast \
    --only-rule force_try \
    --only-rule force_unwrapping \
    "${swift_targets[@]}" > "$swift_report"
  SWIFTLINT_EXIT=$?
  set -e
  if [[ "$SWIFTLINT_EXIT" -ne 0 ]] && [[ ! -s "$swift_report" ]]; then
    echo "❌ SwiftLint failed to execute."
    exit 1
  fi
  if [[ "$SWIFTLINT_EXIT" -ne 0 ]]; then
    echo "⚠️  SwiftLint returned non-zero status; continuing with generated report."
  fi
}

run_dast_checks() (
  set -euo pipefail

  local report_dir="$1"
  local report_dir_abs
  report_dir_abs="$(cd "$report_dir" && pwd)"

  local base_host="${DAST_BASE_HOST:-127.0.0.1}"
  local base_port="${DAST_BASE_PORT:-8787}"
  local base_url="${DAST_BASE_URL:-http://${base_host}:${base_port}}"
  local openapi_url="${DAST_OPENAPI_URL:-${base_url}/openapi.json}"

  local run_schemathesis="${RUN_SCHEMATHESIS:-true}"
  local run_zap="${RUN_ZAP:-true}"
  local run_token_capture_dast="${RUN_TOKEN_CAPTURE_DAST:-auto}" # true|false|auto
  local fail_on_high_critical="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
  local zap_cli_cmd="${ZAP_CLI_CMD:-/Applications/ZAP.app/Contents/MacOS/ZAP.sh}"

  local token_capture_port="${TOKEN_CAPTURE_DAST_PORT:-8088}"
  local token_capture_url="${TOKEN_CAPTURE_DAST_URL:-http://127.0.0.1:${token_capture_port}}"
  local dast_app_python="${DAST_APP_PYTHON:-./teller-venv/bin/python}"

  local schemathesis_seed="${SCHEMATHESIS_SEED:-424242}"
  local schemathesis_max_examples="${SCHEMATHESIS_MAX_EXAMPLES:-25}"
  local zap_classification_target="${ZAP_CLASSIFICATION_TARGET:-${base_url}/health}"

  if [[ ! -x "$dast_app_python" ]]; then
    dast_app_python="python3"
  fi

  local classifier_api_pid=""
  local token_capture_pid=""

  cleanup() {
    if [[ -n "$token_capture_pid" ]] && kill -0 "$token_capture_pid" >/dev/null 2>&1; then
      kill "$token_capture_pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "$classifier_api_pid" ]] && kill -0 "$classifier_api_pid" >/dev/null 2>&1; then
      kill "$classifier_api_pid" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup EXIT

  #R035: Start local classification API automatically for DAST execution.
  echo "▶ Starting local classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
  TELLER_CLASSIFIER_API_HOST="$base_host" TELLER_CLASSIFIER_API_PORT="$base_port" \
    "$dast_app_python" "./14_run_classification_api.py" >"${report_dir_abs}/classification-api.log" 2>&1 &
  classifier_api_pid="$!"
  wait_for_http "${base_url}/health" 45

  #R045: Run Schemathesis and ZAP quick scans with configurable targets and gating.
  if [[ "$run_schemathesis" == "true" ]]; then
    require_command schemathesis
    print_tool_header \
      "Schemathesis" \
      "Property-based API testing driven by the OpenAPI specification." \
      "Finds contract mismatches by generating and exercising request scenarios." \
      "https://schemathesis.readthedocs.io/"
    echo "▶ Running Schemathesis against ${openapi_url}"
    set +e
    schemathesis run "$openapi_url" \
      --url "$base_url" \
      --seed "$schemathesis_seed" \
      --max-examples "$schemathesis_max_examples" \
      --report junit \
      --report-junit-path "${report_dir_abs}/schemathesis-junit.xml" \
      | tee "${report_dir_abs}/schemathesis.log"
    SCHEMATHESIS_EXIT=${PIPESTATUS[0]}
    set -e
    if [[ "$SCHEMATHESIS_EXIT" -gt 1 ]]; then
      echo "❌ Schemathesis failed to execute."
      exit 1
    fi
    if [[ "$SCHEMATHESIS_EXIT" -eq 1 ]]; then
      echo "⚠️  Schemathesis found API contract issues; continuing to ZAP and Dynamic Application Security Testing (DAST) gating."
    fi
  fi

  if [[ "$run_zap" == "true" ]]; then
    if [[ ! -x "$zap_cli_cmd" ]]; then
      echo "❌ Missing ZAP CLI executable: $zap_cli_cmd"
      echo "Install prerequisites with ./01_install_prerequisites.sh or set ZAP_CLI_CMD."
      exit 1
    fi
    run_zap_quick_scan \
      "$zap_cli_cmd" \
      "$zap_classification_target" \
      "${report_dir_abs}/zap-classification.html" \
      "${report_dir_abs}/zap-classification.log"
  fi

  #R040: Support optional token-capture DAST coverage with auto-detection.
  if [[ "$run_token_capture_dast" == "auto" ]]; then
    if [[ -f "$HOME/.teller/application_id.txt" ]]; then
      run_token_capture_dast="true"
    else
      run_token_capture_dast="false"
    fi
  fi

  if [[ "$run_token_capture_dast" == "true" ]]; then
    echo "▶ Starting token capture server for Dynamic Application Security Testing (DAST) at ${token_capture_url}"
    "$dast_app_python" "./teller/teller_connect_token_server.py" --no-open --mode manage --port "$token_capture_port" \
      >"${report_dir_abs}/token-capture.log" 2>&1 &
    token_capture_pid="$!"
    wait_for_http "${token_capture_url}/api/status" 45

    if [[ "$run_zap" == "true" ]]; then
      run_zap_quick_scan \
        "$zap_cli_cmd" \
        "$token_capture_url" \
        "${report_dir_abs}/zap-token-capture.html" \
        "${report_dir_abs}/zap-token-capture.log"
    fi
  else
    echo "ℹ️  Token capture Dynamic Application Security Testing (DAST) skipped (set RUN_TOKEN_CAPTURE_DAST=true and ensure ~/.teller/application_id.txt exists)."
  fi

  local high_alerts=0
  local alerts
  for zap_json in "${report_dir_abs}/zap-classification.json" "${report_dir_abs}/zap-token-capture.json"; do
    if [[ -f "$zap_json" ]]; then
      alerts="$(python3 - <<'PY' "$zap_json"
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)
sites = payload.get("site", []) if isinstance(payload, dict) else []
count = 0
for site in sites:
    for alert in site.get("alerts", []):
        try:
            risk = int(alert.get("riskcode", "-1"))
        except ValueError:
            risk = -1
        if risk >= 3:
            count += 1
print(count)
PY
)"
      high_alerts=$((high_alerts + alerts))
    fi
  done

  if [[ ! -f "${report_dir_abs}/zap-classification.json" ]] && [[ ! -f "${report_dir_abs}/zap-token-capture.json" ]]; then
    echo "ℹ️  ZAP CLI quick scan produced HTML/log output only; JSON alert parsing skipped."
  fi

  echo "Dynamic Application Security Testing (DAST) high/critical alert count: ${high_alerts}"
  if [[ "$fail_on_high_critical" == "true" ]] && (( high_alerts > 0 )); then
    echo "❌ Dynamic Application Security Testing (DAST) gate failed: High/Critical ZAP alerts detected."
    exit 1
  fi

  echo "✅ Dynamic Application Security Testing (DAST) checks completed."
)

ensure_security_venv
export PATH="${SECURITY_VENV_DIR}/bin:${PATH}"

#R010: Ensure pip-audit inspects project dependencies, not security toolchain env.
configure_pip_audit_python() {
  local project_python=""
  if [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python3" ]]; then
    project_python="${VIRTUAL_ENV}/bin/python3"
  elif [[ -x "./teller-venv/bin/python3" ]]; then
    project_python="./teller-venv/bin/python3"
  fi

  if [[ -n "$project_python" ]]; then
    export PIPAPI_PYTHON_LOCATION="$project_python"
    echo "▶ pip-audit target interpreter: ${PIPAPI_PYTHON_LOCATION}"
  else
    unset PIPAPI_PYTHON_LOCATION || true
    echo "ℹ️  pip-audit target interpreter: default environment"
  fi
}

configure_pip_audit_python

if [[ "$RUN_SAST" == "true" ]]; then
  #R020: Run SAST scanners and persist machine-readable artifacts.
  require_command semgrep
  require_command bandit
  require_command pip-audit
  require_command detect-secrets

  print_tool_header \
    "Semgrep" \
    "Static pattern-based scanning for security and correctness issues." \
    "Combines community and repo custom rules across tracked source files." \
    "https://semgrep.dev/docs/"
  echo "▶ Running Semgrep"
  semgrep scan \
    --config "p/security-audit" \
    --config "p/python" \
    --config ".semgrep.yml" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    .

  print_tool_header \
    "Bandit" \
    "Static security analyzer for Python source code." \
    "Flags known insecure coding patterns and risky API usage." \
    "https://bandit.readthedocs.io/"
  echo "▶ Running Bandit"
  #R025: Distinguish scanner findings from scanner execution failures.
  set +e
  bandit -q -r ./teller -c ./.bandit -f json -o "${REPORT_DIR}/bandit.json"
  BANDIT_EXIT=$?
  set -e
  if [[ "$BANDIT_EXIT" -gt 1 ]]; then
    echo "❌ Bandit failed to execute."
    exit 1
  fi

  print_tool_header \
    "pip-audit" \
    "Dependency vulnerability scanner for installed Python packages." \
    "Maps local dependencies to public vulnerability advisories." \
    "https://github.com/pypa/pip-audit"
  echo "▶ Running pip-audit"
  set +e
  pip-audit --format json --output "${REPORT_DIR}/pip-audit.json"
  PIP_AUDIT_EXIT=$?
  set -e
  if [[ "$PIP_AUDIT_EXIT" -gt 1 ]]; then
    echo "❌ pip-audit failed to execute."
    exit 1
  fi

  print_tool_header \
    "detect-secrets" \
    "Scans repository files for high-entropy and known secret formats." \
    "Helps catch accidentally committed credentials before release." \
    "https://github.com/Yelp/detect-secrets"
  echo "▶ Running detect-secrets"
  detect-secrets scan --all-files --force-use-all-plugins \
    --exclude-files '(^\.git/|^teller-venv/|^\.security-venv/|^\.security-reports/|^backups/|^archive/backup_extracts/|^bank_statements/|^teller-connect-ui/|^macos-ui/\.derivedData-ui-tests/|^macos-ui/\.build/)' \
    > "${REPORT_DIR}/detect-secrets.json"

  run_swift_sast "${REPORT_DIR}/swiftlint.json"

  #R030: Produce consolidated SAST gate summary and enforce blocking policy.
  python3 - <<'PY' "${REPORT_DIR}" "${FAIL_ON_HIGH_CRITICAL}"
import json
import os
import sys
from pathlib import Path

report_dir = Path(sys.argv[1])
fail_on_high = sys.argv[2].lower() == "true"

semgrep_path = report_dir / "semgrep.json"
bandit_path = report_dir / "bandit.json"
pip_audit_path = report_dir / "pip-audit.json"
secrets_path = report_dir / "detect-secrets.json"
swiftlint_path = report_dir / "swiftlint.json"

for required in [semgrep_path, bandit_path, pip_audit_path, secrets_path, swiftlint_path]:
    if not required.exists():
        print(f"Missing report file: {required}")
        sys.exit(1)

with semgrep_path.open("r", encoding="utf-8") as fh:
    semgrep = json.load(fh)
semgrep_results = semgrep.get("results", []) if isinstance(semgrep, dict) else []
semgrep_high = sum(1 for item in semgrep_results if item.get("extra", {}).get("severity") == "ERROR")
semgrep_total = len(semgrep_results)

with bandit_path.open("r", encoding="utf-8") as fh:
    bandit = json.load(fh)
bandit_results = bandit.get("results", []) if isinstance(bandit, dict) else []
bandit_high = sum(1 for item in bandit_results if item.get("issue_severity") == "HIGH")
bandit_total = len(bandit_results)

with pip_audit_path.open("r", encoding="utf-8") as fh:
    pip_audit = json.load(fh)
if isinstance(pip_audit, list):
    dep_vulns = sum(len(item.get("vulns", [])) for item in pip_audit)
elif isinstance(pip_audit, dict) and isinstance(pip_audit.get("dependencies"), list):
    dep_vulns = sum(
        len(dep.get("vulns", []))
        for dep in pip_audit.get("dependencies", [])
        if isinstance(dep, dict)
    )
else:
    dep_vulns = len(pip_audit.get("vulns", [])) if isinstance(pip_audit, dict) else 0

with secrets_path.open("r", encoding="utf-8") as fh:
    secrets = json.load(fh)
secret_results = secrets.get("results", {}) if isinstance(secrets, dict) else {}
secret_findings = 0
for findings in secret_results.values():
    if isinstance(findings, list):
        secret_findings += len(findings)

with swiftlint_path.open("r", encoding="utf-8") as fh:
    swiftlint = json.load(fh)
swiftlint_results = swiftlint if isinstance(swiftlint, list) else []
swiftlint_high = sum(1 for item in swiftlint_results if str(item.get("severity", "")).lower() == "error")
swiftlint_total = len(swiftlint_results)

high_critical_total = semgrep_high + bandit_high + secret_findings + swiftlint_high

summary = {
    "semgrep_total": semgrep_total,
    "semgrep_high_critical": semgrep_high,
    "bandit_total": bandit_total,
    "bandit_high_critical": bandit_high,
    "pip_audit_vulnerabilities": dep_vulns,
    "detect_secrets_findings": secret_findings,
    "swiftlint_total": swiftlint_total,
    "swiftlint_high_critical": swiftlint_high,
    "high_critical_total": high_critical_total,
    "gate_failed": fail_on_high and high_critical_total > 0,
}

summary_path = report_dir / "sast-summary.json"
with summary_path.open("w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
    fh.write("\n")

print("Static Application Security Testing (SAST) summary")
print(json.dumps(summary, indent=2))

if fail_on_high and high_critical_total > 0:
    print("❌ Static Application Security Testing (SAST) gate failed: High/Critical findings detected.")
    sys.exit(1)
PY
fi

if [[ "$RUN_DAST" == "true" ]]; then
  run_dast_checks "$REPORT_DIR"
fi

#R050: Emit explicit completion status and artifact location for operators.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
