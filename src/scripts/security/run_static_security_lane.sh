#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
security_init_repo_root "$SCRIPT_PATH"
REPO_ROOT="${SECURITY_REPO_ROOT}"
echo "running SAST (Static Application Security Testing)"

#R001: Static lane prints explicit startup banner before scanner orchestration.
#R005: Static lane resolves repo root and executes with strict shell settings.
#R010: Static lane bootstraps isolated security toolchain venv before scans.
#R015: Static lane defaults to RUN_SAST=true and RUN_DAST=false behavior.
#R020: Static lane prints completion markers and report artifact location.
#R025: Static lane executes Ruff and persists ruff.json into report artifacts.
#R030: Static lane includes Ruff findings in centralized blocking SAST gate.
#R035: Static lane excludes generated cache/report paths from secret scanning.
#R040: Static lane runs gitleaks against tracked-source snapshot input.
#R045: Static lane emits detailed Semgrep status in unsuppressed runs.
#R047: Static lane invokes Semgrep without --quiet suppression flag.
#R050: Static lane emits detailed Bandit status in unsuppressed runs.
#R055: Static lane emits detailed pip-audit status in unsuppressed runs.
#R060: Static lane emits detailed detect-secrets status in unsuppressed runs.
#R065: Static lane emits detailed Ruff status in unsuppressed runs.
#R070: Static lane emits detailed ShellCheck status in unsuppressed runs.
#R080: Static lane relies on shared cache env to keep __pycache__ under artifacts/cache.
#R090: Static lane enforces medium-or-higher blocker policy across scanners.
#R100: Static lane redacts persisted Schemathesis token-bearing artifacts.
#R105: Static lane enforces hash-pinned security requirements for toolchain bootstrap.
#R110: Static lane emits SBOM + signing scaffold artifacts for supply-chain visibility.
REPORT_DIR="${SECURITY_REPORT_DIR:-./artifacts/security/reports}"
RUN_SAST="${RUN_SAST:-true}"
RUN_DAST="${RUN_DAST:-false}"
RUN_SWIFT_SAST="${RUN_SWIFT_SAST:-true}"
#R015: Support configurable execution lanes and report destination.
#R090: Default financial-app policy blocks medium-or-higher security findings.
FAIL_ON_MEDIUM_OR_HIGHER="${SECURITY_FAIL_ON_MEDIUM_OR_HIGHER:-${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./artifacts/venv/security}"
#R105: Runner-owned security lockfile (repo override else runner default).
SECURITY_REQUIREMENTS_FILE="${SECURITY_REQUIREMENTS_FILE:-$(security_resolve_asset requirements/security/requirements-security.txt)}"
RUNTIME_REQUIREMENTS_FILE="${RUNTIME_REQUIREMENTS_FILE:-./requirements.txt}"
#R090: Security tool config (repo override else runner default).
SECURITY_CONFIG_DIR="${SECURITY_CONFIG_DIR:-$(security_resolve_asset config/security)}"
#R090: Resolve each config file independently (a repo may have a partial config/security dir).
SEMGREP_CONFIG_PATH="${SEMGREP_CONFIG_PATH:-$(security_resolve_asset config/security/semgrep.yml)}"
BANDIT_CONFIG_PATH="${BANDIT_CONFIG_PATH:-$(security_resolve_asset config/security/bandit.yml)}"
GITLEAKS_IGNORE_PATH="${GITLEAKS_IGNORE_PATH:-$(security_resolve_asset config/security/gitleaksignore)}"
SUPPLY_CHAIN_ARTIFACTS_DIR="${SUPPLY_CHAIN_ARTIFACTS_DIR:-${REPORT_DIR}}"
#R115: Default supply-chain signing mode to required in CI when unset.
if [[ -z "${SUPPLY_CHAIN_SIGNING_MODE:-}" ]]; then
  if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
    SUPPLY_CHAIN_SIGNING_MODE="required"
  else
    SUPPLY_CHAIN_SIGNING_MODE="scaffold"
  fi
fi
WRITE_TOKEN_PSA_ITEM="${WRITE_TOKEN_PSA_ITEM:-TELLER_CLASSIFIER_WRITE_TOKEN}"
WRITE_TOKEN_HEADER_NAME="${WRITE_TOKEN_HEADER_NAME:-X-Teller-Write-Token}"

mkdir -p "$REPORT_DIR"

python_interpreter_usable() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" -c "import site" >/dev/null 2>&1
}

#R001: Prefer project venv when available.
if [[ -d "./${VENV_NAME}" ]] && [[ -f "./${VENV_NAME}/bin/activate" ]]; then
  if ! python_interpreter_usable "./${VENV_NAME}/bin/python"; then
    echo "⚠️  Skipping ${VENV_NAME} activation because its interpreter is not usable."
  else
  # shellcheck disable=SC1091
    source "./${VENV_NAME}/bin/activate"
  fi
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    echo "Install prerequisites with ./01_install_prerequisites.sh, then run ./03_prepare_supply_chain_integrity.sh and pip install --require-hashes -r ${SECURITY_REQUIREMENTS_FILE}"
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "❌ Missing required file: $1"
    exit 1
  fi
}

count_report_findings() {
  local mode="$1"
  local report_path="$2"
  python3 - <<'PY' "$mode" "$report_path"
import json
import sys

mode = sys.argv[1]
path = sys.argv[2]

with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

count = 0
if mode == "semgrep":
    count = len(payload.get("results", [])) if isinstance(payload, dict) else 0
elif mode == "bandit":
    count = len(payload.get("results", [])) if isinstance(payload, dict) else 0
elif mode == "pip-audit":
    if isinstance(payload, list):
        count = sum(len(item.get("vulns", [])) for item in payload if isinstance(item, dict))
    elif isinstance(payload, dict) and isinstance(payload.get("dependencies"), list):
        count = sum(len(dep.get("vulns", [])) for dep in payload.get("dependencies", []) if isinstance(dep, dict))
    elif isinstance(payload, dict):
        count = len(payload.get("vulns", [])) if isinstance(payload.get("vulns", []), list) else 0
elif mode == "detect-secrets":
    if isinstance(payload, dict) and isinstance(payload.get("results"), dict):
        count = sum(len(v) for v in payload.get("results", {}).values() if isinstance(v, list))
elif mode == "ruff":
    count = len(payload) if isinstance(payload, list) else 0
elif mode == "shellcheck":
    count = len(payload) if isinstance(payload, list) else 0

print(count)
PY
}

print_semgrep_findings() {
  local report_path="$1"
  python3 - <<'PY' "$report_path"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print(f"⚠️  Semgrep findings unavailable: report missing at {path}")
    raise SystemExit(0)

try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"⚠️  Semgrep findings unavailable: unable to parse {path}: {exc}")
    raise SystemExit(0)

results = payload.get("results", []) if isinstance(payload, dict) else []
if not results:
    print("✅ Semgrep findings: none")
    raise SystemExit(0)

print(f"⚠️  Semgrep findings ({len(results)}):")
for item in results:
    extra = item.get("extra", {}) if isinstance(item, dict) else {}
    severity = str(extra.get("severity", "UNKNOWN"))
    check_id = str(item.get("check_id", "unknown-rule"))
    file_path = str(item.get("path", "unknown-path"))
    line = item.get("start", {}).get("line", "?")
    message = str(extra.get("message", "no message")).replace("\n", " ").strip()
    print(f"  - [{severity}] {check_id} @ {file_path}:{line}")
    print(f"    {message}")
PY
}

print_tool_header() {
  # Delimit each security tool execution with a boxed descriptor header.
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
  local security_pip="${SECURITY_VENV_DIR}/bin/pip"
  local security_semgrep="${SECURITY_VENV_DIR}/bin/semgrep"
  local security_ruff="${SECURITY_VENV_DIR}/bin/ruff"
  local needs_toolchain="false"
  if [[ "$RUN_SAST" == "true" ]]; then
    if [[ ! -x "$security_semgrep" || ! -x "$security_ruff" ]]; then
      needs_toolchain="true"
    fi
  elif [[ ! -x "$security_semgrep" ]]; then
    needs_toolchain="true"
  fi

  if [[ ! -d "$SECURITY_VENV_DIR" || ! -x "$security_pip" ]]; then
    # Only rebuild partial environments when install flow requires pip.
    if [[ -d "$SECURITY_VENV_DIR" && ! -x "$security_pip" && "$needs_toolchain" != "true" ]]; then
      :
    else
    echo "▶ Creating isolated security virtualenv at ${SECURITY_VENV_DIR}"
    python3 -m venv "$SECURITY_VENV_DIR"
    fi
  fi

  security_pip="${SECURITY_VENV_DIR}/bin/pip"
  security_semgrep="${SECURITY_VENV_DIR}/bin/semgrep"
  security_ruff="${SECURITY_VENV_DIR}/bin/ruff"
  needs_toolchain="false"
  if [[ "$RUN_SAST" == "true" ]]; then
    if [[ ! -x "$security_semgrep" || ! -x "$security_ruff" ]]; then
      needs_toolchain="true"
    fi
  elif [[ ! -x "$security_semgrep" ]]; then
    needs_toolchain="true"
  fi
  if [[ "$needs_toolchain" == "true" ]]; then
    require_hashed_requirements_file "$SECURITY_REQUIREMENTS_FILE"
    echo "▶ Installing security toolchain into ${SECURITY_VENV_DIR}"
    "$security_pip" install --upgrade pip
    "$security_pip" install --require-hashes -r "$SECURITY_REQUIREMENTS_FILE"
  fi
}

requirements_file_has_hashes() {
  local requirements_file="$1"
  python3 - <<'PY' "$requirements_file"
from pathlib import Path
import sys

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit(1)
content = path.read_text(encoding="utf-8", errors="replace")
raise SystemExit(0 if "--hash=sha256:" in content else 1)
PY
}

require_hashed_requirements_file() {
  local requirements_file="$1"
  require_file "$requirements_file"
  if ! requirements_file_has_hashes "$requirements_file"; then
    echo "❌ Requirements file is not hash-pinned: ${requirements_file}"
    echo "Run ./03_prepare_supply_chain_integrity.sh to regenerate lockfiles with hashes."
    exit 1
  fi
}

generate_supply_chain_artifacts() {
  require_hashed_requirements_file "$RUNTIME_REQUIREMENTS_FILE"
  require_hashed_requirements_file "$SECURITY_REQUIREMENTS_FILE"
  local generator_script="${SECURITY_RUNNER_HOME}/src/scripts/security/generate_supply_chain_artifacts.py"
  require_file "$generator_script"
  echo "▶ Generating supply-chain artifacts (SBOM + signing scaffold)"
  python3 "$generator_script" \
    --runtime-lock "$RUNTIME_REQUIREMENTS_FILE" \
    --security-lock "$SECURITY_REQUIREMENTS_FILE" \
    --output-dir "$SUPPLY_CHAIN_ARTIFACTS_DIR" \
    --signing-mode "$SUPPLY_CHAIN_SIGNING_MODE" \
    > "${REPORT_DIR}/supply-chain-artifacts.json"
}

security_toolchain_usable() {
  local security_semgrep="${SECURITY_VENV_DIR}/bin/semgrep"
  if [[ ! -x "$security_semgrep" ]]; then
    return 1
  fi
  "$security_semgrep" --version >/dev/null 2>&1
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  local curl_args=(-fsS)
  if [[ "$url" == https://* ]]; then
    curl_args+=(-k)
  fi
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if curl "${curl_args[@]}" "$url" >/dev/null 2>&1; then
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
  local zap_home_dir="$2"
  local zap_quiet="$3"
  local target_url="$4"
  local html_report="$5"
  local log_report="$6"
  print_tool_header \
    "OWASP ZAP" \
    "Dynamic scan of live HTTP endpoints for common web vulnerabilities." \
    "Uses quick scan mode to spider and actively probe reachable routes." \
    "https://www.zaproxy.org/"
  echo "▶ Running OWASP ZAP quick scan (CLI) against ${target_url}"
  echo "▶ ZAP home directory: ${zap_home_dir}"
  if [[ "$zap_quiet" == "true" ]]; then
    "$zap_cli_cmd" -cmd \
      -dir "$zap_home_dir" \
      -quickurl "$target_url" \
      -quickout "$html_report" \
      -quickprogress \
      -silent | tee "$log_report"
  else
    "$zap_cli_cmd" -cmd \
      -dir "$zap_home_dir" \
      -quickurl "$target_url" \
      -quickout "$html_report" \
      -quickprogress | tee "$log_report"
  fi
}

read_classifier_write_token() {
  # Resolve DAST write token only from 1psa.
  local write_token
  write_token="$(1psa -p "$WRITE_TOKEN_PSA_ITEM")"
  if [[ -z "$write_token" ]]; then
    echo "❌ Failed to read classifier write token from 1psa item: ${WRITE_TOKEN_PSA_ITEM}"
    exit 1
  fi
  printf '%s' "$write_token"
}

run_swift_sast() {
  local swift_report="$1"
  local swift_ui_dir="${SWIFT_UI_DIR:-./src/macos-ui}"
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

run_shellcheck_sast() {
  # Run ShellCheck against shell scripts and persist machine-readable findings.
  local shellcheck_report="$1"
  local shellcheck_targets=()

  require_command shellcheck
  print_tool_header \
    "ShellCheck" \
    "Static analysis for shell scripts to catch correctness and safety issues." \
    "Runs JSON-reporting checks across numbered shell automation scripts." \
    "https://www.shellcheck.net/"
  shopt -s nullglob
  shellcheck_targets=(./[0-9][0-9]_*.sh ./t[0-9][0-9]_*.sh)
  shopt -u nullglob

  if [[ "${#shellcheck_targets[@]}" -eq 0 ]]; then
    printf '[]\n' > "$shellcheck_report"
    echo "ℹ️  ShellCheck skipped (no numbered shell scripts found)."
    return 0
  fi

  echo "▶ Running ShellCheck"
  set +e
  shellcheck --format=json "${shellcheck_targets[@]}" > "$shellcheck_report"
  SHELLCHECK_EXIT=$?
  set -e
  if [[ "$SHELLCHECK_EXIT" -gt 1 ]]; then
    echo "❌ ShellCheck failed to execute."
    exit 1
  fi
  if [[ "$SHELLCHECK_EXIT" -eq 1 ]]; then
    echo "⚠️  ShellCheck reported findings; continuing to centralized SAST gating."
  fi
  #R070: Emit detailed ShellCheck status when output is unsuppressed.
  local shellcheck_findings
  shellcheck_findings="$(count_report_findings "shellcheck" "$shellcheck_report")"
  echo "ℹ️  ShellCheck detailed status: exit_code=${SHELLCHECK_EXIT}; findings=${shellcheck_findings}; report=${shellcheck_report}"
}

run_ruff_sast() {
  #R025: Include Ruff lint scan in SAST reports and summary accounting.
  # Run Ruff static analysis against Python sources and persist JSON findings.
  local ruff_report="$1"

  require_command ruff
  print_tool_header \
    "Ruff" \
    "Fast Python linter for static quality and security-related code checks." \
    "Runs repository lint rules and emits machine-readable JSON findings." \
    "https://docs.astral.sh/ruff/"
  echo "▶ Running Ruff"
  set +e
  ruff check \
    --output-format json \
    --force-exclude \
    --exclude "${VENV_NAME},.venv,mutants,artifacts,.pytest_cache,.ruff_cache,deprecated" \
    . > "$ruff_report"
  RUFF_EXIT=$?
  set -e
  if [[ "$RUFF_EXIT" -gt 1 ]]; then
    echo "❌ Ruff failed to execute."
    exit 1
  fi
  if [[ "$RUFF_EXIT" -eq 1 ]]; then
    echo "⚠️  Ruff reported findings; continuing to centralized SAST gating."
  fi
  #R065: Emit detailed Ruff status when output is unsuppressed.
  local ruff_findings
  ruff_findings="$(count_report_findings "ruff" "$ruff_report")"
  echo "ℹ️  Ruff detailed status: exit_code=${RUFF_EXIT}; findings=${ruff_findings}; report=${ruff_report}"
}

run_gitleaks_sast() {
  #R040: Run gitleaks against a git-tracked working-tree snapshot source.
  # Run gitleaks and preserve JSON findings for centralized secret-leak gating.
  local gitleaks_report="$1"
  local gitleaks_source_dir
  gitleaks_source_dir="$(mktemp -d "${REPORT_DIR}/gitleaks-source.XXXXXX")"

  require_command gitleaks
  require_command git
  #R035: Exclude generated scanner/cache artifacts from detect-secrets input.
  print_tool_header \
    "gitleaks" \
    "Detects hardcoded secrets and credential patterns in tracked files." \
    "Runs repository-focused leak detection and emits JSON findings." \
    "https://github.com/gitleaks/gitleaks"
  # Scan only git-tracked files to avoid scanner output/cache feedback loops.
  while IFS= read -r -d '' tracked_file; do
    if [[ ! -f "$tracked_file" ]]; then
      continue
    fi
    if [[ "$tracked_file" == .cursor/* || "$tracked_file" == .cursor* ]]; then
      continue
    fi
    if [[ "$tracked_file" == artifacts/venv/security/* || \
          "$tracked_file" == artifacts/security/* || \
          "$tracked_file" == artifacts/security-dast/* || \
          "$tracked_file" == artifacts/parallel/* || \
          "$tracked_file" == artifacts/mutation/* || \
          "$tracked_file" == artifacts/fuzz/* || \
          "$tracked_file" == artifacts/macos-ui-regression/* || \
          "$tracked_file" == artifacts/cache/* || \
          "$tracked_file" == .ruff_cache/* || \
          "$tracked_file" == .pytest_cache/* || \
          "$tracked_file" == __pycache__/* ]]; then
      continue
    fi
    mkdir -p "${gitleaks_source_dir}/$(dirname "$tracked_file")"
    cp "$tracked_file" "${gitleaks_source_dir}/${tracked_file}"
  done < <(git ls-files -z)
  echo "▶ Running gitleaks"
  set +e
  gitleaks detect \
    --source "$gitleaks_source_dir" \
    --no-git \
    --gitleaks-ignore-path "$GITLEAKS_IGNORE_PATH" \
    --report-format json \
    --report-path "$gitleaks_report"
  GITLEAKS_EXIT=$?
  set -e
  rm -rf "$gitleaks_source_dir"
  if [[ "$GITLEAKS_EXIT" -gt 1 ]]; then
    echo "❌ gitleaks failed to execute."
    exit 1
  fi
  if [[ "$GITLEAKS_EXIT" -eq 1 ]]; then
    echo "⚠️  gitleaks reported findings; continuing to centralized SAST gating."
  fi

  if [[ ! -s "$gitleaks_report" ]]; then
    printf '[]\n' > "$gitleaks_report"
  fi
}

run_dast_checks() (
  set -euo pipefail

  run_category_integrity_checks() {
    local report_dir_abs="$1"
    local integrity_report_path="${report_dir_abs}/category-integrity.json"
    local seed_sql_path="./src/sql/postgres/teller_nys_snw_category.sql"
    local strict_mode="${DAST_CATEGORY_INTEGRITY_STRICT:-true}"

    echo "▶ Running post-DAST category integrity checks"
    set +e
    PYTHONPATH="${dast_integrity_pythonpath:-${PYTHONPATH:-}}" "$dast_app_python"       "./tests/py/security/category_integrity_check.py"       "$integrity_report_path"       "$seed_sql_path"       "$strict_mode"
    local integrity_exit=$?
    set -e
    if [[ "$integrity_exit" -ne 0 ]]; then
      return "$integrity_exit"
    fi
  }

  prepare_schemathesis_openapi_fixture() {
    local source_openapi_url="$1"
    local source_base_url="$2"
    local output_schema_path="$3"
    local write_token="$4"
    local write_token_header_name="$5"
    python3 "./tests/py/security/schemathesis_fixture_prep.py"       "$source_openapi_url"       "$source_base_url"       "$output_schema_path"       "$write_token"       "$write_token_header_name"       ""       "${DAST_RUN_ID:-unknown}"
  }

  run_delete_category_contract_check() {
    local schema_path="$1"
    local source_base_url="$2"
    local output_json_path="$3"
    local write_token="$4"
    local write_token_header_name="$5"
    python3 "./tests/py/security/delete_category_contract_check.py"       "$schema_path"       "$source_base_url"       "$output_json_path"       "$write_token"       "$write_token_header_name"       "${DAST_RUN_ID:-unknown}"
  }

  local report_dir="$1"
  local report_dir_abs
  report_dir_abs="$(cd "$report_dir" && pwd)"

  local base_host="${DAST_BASE_HOST:-127.0.0.1}"
  local base_port="${DAST_BASE_PORT:-8787}"
  local base_url="${DAST_BASE_URL:-https://${base_host}:${base_port}}"
  local loopback_http_pattern='^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?($|/)'
  if [[ "$base_url" == http://* ]] && [[ ! "$base_url" =~ $loopback_http_pattern ]]; then
    echo "❌ DAST_BASE_URL must use https:// unless targeting loopback HTTP (received: ${base_url})"
    exit 1
  fi
  local openapi_url="${DAST_OPENAPI_URL:-${base_url}/openapi.json}"
  if [[ "$openapi_url" == http://* ]] && [[ ! "$openapi_url" =~ $loopback_http_pattern ]]; then
    echo "❌ DAST_OPENAPI_URL must use https:// unless targeting loopback HTTP (received: ${openapi_url})"
    exit 1
  fi

  local run_schemathesis="${RUN_SCHEMATHESIS:-true}"
  local schemathesis_fail_on_findings="${SCHEMATHESIS_FAIL_ON_FINDINGS:-true}"
  local run_zap="${RUN_ZAP:-true}"
  local reuse_existing_api="${DAST_REUSE_EXISTING_API:-${MACOS_UI_DAST_REUSE_EXISTING_API:-false}}"
  local run_token_capture_dast="${RUN_TOKEN_CAPTURE_DAST:-auto}" # true|false|auto
  local fail_on_high_critical="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
  local dast_write_token
  dast_write_token="$(read_classifier_write_token)"
  local zap_cli_cmd="${ZAP_CLI_CMD:-/Applications/ZAP.app/Contents/MacOS/ZAP.sh}"
  local zap_home_dir="${ZAP_HOME_DIR:-${REPO_ROOT}/artifacts/security/zap-home}"
  # Keep ZAP quick-scan output visible by default unless explicitly silenced.
  local zap_quiet="${ZAP_QUIET:-false}"

  local dast_app_python="${DAST_APP_PYTHON:-./teller-venv/bin/python}"

  local schemathesis_seed="${SCHEMATHESIS_SEED:-424242}"
  local schemathesis_max_examples="${SCHEMATHESIS_MAX_EXAMPLES:-25}"
  local zap_classification_target="${ZAP_CLASSIFICATION_TARGET:-${base_url}/health}"

  if [[ ! -x "$dast_app_python" ]]; then
    dast_app_python="python3"
  fi

  local classifier_api_pid=""
  local token_capture_pid=""

  trap 'if [[ -n "$token_capture_pid" ]] && kill -0 "$token_capture_pid" >/dev/null 2>&1; then kill "$token_capture_pid" >/dev/null 2>&1 || true; fi; if [[ -n "$classifier_api_pid" ]] && kill -0 "$classifier_api_pid" >/dev/null 2>&1; then kill "$classifier_api_pid" >/dev/null 2>&1 || true; fi' EXIT
  mkdir -p "$zap_home_dir"

  # Start local classification API automatically for DAST execution.
  if [[ "$reuse_existing_api" == "true" ]]; then
    echo "▶ Reusing existing classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
  else
    echo "▶ Starting local classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
    TELLER_CLASSIFIER_API_HOST="$base_host" TELLER_CLASSIFIER_API_PORT="$base_port" \
      "$dast_app_python" "./09_run_classification_api.py" >"${report_dir_abs}/classification-api.log" 2>&1 &
    classifier_api_pid="$!"
  fi
  wait_for_http "${base_url}/health" 45

  # Run Schemathesis and ZAP quick scans with configurable targets and gating.
  if [[ "$run_schemathesis" == "true" ]]; then
    require_command schemathesis
    print_tool_header \
      "Schemathesis" \
      "Property-based API testing driven by the OpenAPI specification." \
      "Finds contract mismatches by generating and exercising request scenarios." \
      "https://schemathesis.readthedocs.io/"
    echo "▶ Running Schemathesis against ${openapi_url}"
    local schemathesis_location="$openapi_url"
    local schemathesis_openapi_fixture="${report_dir_abs}/schemathesis-openapi.json"
    if prepare_schemathesis_openapi_fixture "$openapi_url" "$base_url" "$schemathesis_openapi_fixture" "$dast_write_token" "$WRITE_TOKEN_HEADER_NAME" \
      > "${report_dir_abs}/schemathesis-fixture.json"; then
      schemathesis_location="$schemathesis_openapi_fixture"
      echo "▶ Schemathesis fixture prepared at ${schemathesis_location}"
    else
      echo "⚠️  Schemathesis fixture preparation failed; using live OpenAPI URL."
    fi
    echo "▶ Running deterministic delete-category contract check"
    run_delete_category_contract_check \
      "$schemathesis_location" \
      "$base_url" \
      "${report_dir_abs}/schemathesis-delete-category-contract.json" \
      "$dast_write_token" \
      "$WRITE_TOKEN_HEADER_NAME" \
      | tee "${report_dir_abs}/schemathesis-delete-category-contract.log"
    #R100: Write raw output temporarily, then persist only token-redacted artifacts.
    local schemathesis_raw_log="${report_dir_abs}/schemathesis-raw.log"
    set +e
    (
      cd "$report_dir_abs"
      schemathesis run "$schemathesis_location" \
        --url "$base_url" \
        --header "${WRITE_TOKEN_HEADER_NAME}: ${dast_write_token}" \
        --mode positive \
        --seed "$schemathesis_seed" \
        --max-examples "$schemathesis_max_examples" \
        --report junit \
        --report-junit-path "${report_dir_abs}/schemathesis-junit.xml"
    ) > "$schemathesis_raw_log" 2>&1
    SCHEMATHESIS_EXIT=$?
    set -e
    redact_secret_in_file "$schemathesis_raw_log" "${report_dir_abs}/schemathesis.log" "$dast_write_token"
    rm -f "$schemathesis_raw_log"
    if [[ -f "${report_dir_abs}/schemathesis-junit.xml" ]]; then
      redact_secret_in_place "${report_dir_abs}/schemathesis-junit.xml" "$dast_write_token"
    fi
    if [[ "$SCHEMATHESIS_EXIT" -gt 1 ]]; then
      echo "❌ Schemathesis failed to execute."
      exit 1
    fi
    if [[ "$SCHEMATHESIS_EXIT" -eq 1 ]]; then
      if [[ "$schemathesis_fail_on_findings" == "true" ]]; then
        echo "❌ Schemathesis found API contract issues."
        exit 1
      fi
      echo "⚠️  Schemathesis found API contract issues; continuing because SCHEMATHESIS_FAIL_ON_FINDINGS=false."
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
      "$zap_home_dir" \
      "$zap_quiet" \
      "$zap_classification_target" \
      "${report_dir_abs}/zap-classification.html" \
      "${report_dir_abs}/zap-classification.log"
  fi

  # Support optional token-capture DAST coverage with auto-detection.
  if [[ "$run_token_capture_dast" == "auto" ]]; then
    if [[ -f "$HOME/.teller/application_id.txt" ]]; then
      run_token_capture_dast="true"
    else
      run_token_capture_dast="false"
    fi
  fi

  if [[ "$run_token_capture_dast" == "true" ]]; then
    echo "ℹ️  Token capture Dynamic Application Security Testing (DAST) moved to macOS UI Connect WebView coverage."
    echo "ℹ️  Legacy localhost token-capture endpoint scan is deprecated and no longer runs."
  else
    echo "ℹ️  Token capture Dynamic Application Security Testing (DAST) skipped."
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
count = 0
if isinstance(payload, dict) and isinstance(payload.get("site"), list):
    for site in payload.get("site", []):
        for alert in site.get("alerts", []):
            try:
                risk = int(alert.get("riskcode", "-1"))
            except ValueError:
                risk = -1
            if risk >= 3:
                count += 1
elif isinstance(payload, dict) and isinstance(payload.get("alerts"), list):
    for alert in payload.get("alerts", []):
        risk = str(alert.get("risk", "")).lower()
        if risk in {"high", "critical"}:
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

  # Enforce post-DAST category table integrity invariants.
  run_category_integrity_checks "$report_dir_abs"

  echo "✅ Dynamic Application Security Testing (DAST) checks completed."
)

ensure_security_venv
if security_toolchain_usable; then
  export PATH="${SECURITY_VENV_DIR}/bin:${PATH}"
else
  echo "⚠️  Security venv toolchain is not executable in this environment; using system-installed security tools."
fi

#R010: Ensure pip-audit inspects project dependencies, not security toolchain env.
configure_pip_audit_python() {
  local project_python=""
  if [[ -n "${VIRTUAL_ENV:-}" ]] && python_interpreter_usable "${VIRTUAL_ENV}/bin/python3"; then
    project_python="${VIRTUAL_ENV}/bin/python3"
  elif python_interpreter_usable "./${VENV_NAME}/bin/python3"; then
    project_python="./${VENV_NAME}/bin/python3"
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
#R110: Supply-chain SBOM/signing requires hash-pinned lockfiles; presence-gate it for repos without them.
if [[ "${RUN_SUPPLY_CHAIN:-true}" == "true" ]] && requirements_file_has_hashes "$RUNTIME_REQUIREMENTS_FILE"; then
  generate_supply_chain_artifacts
else
  echo "ℹ️  Supply-chain artifact generation skipped (RUN_SUPPLY_CHAIN!=true or runtime requirements not hash-pinned)."
fi

if [[ "$RUN_SAST" == "true" ]]; then
  #R020: Run SAST scanners and persist machine-readable artifacts.
  require_command semgrep
  require_command bandit
  require_command pip-audit
  require_command detect-secrets
  require_command ruff
  require_command shellcheck
  require_command gitleaks
  require_file "$SEMGREP_CONFIG_PATH"
  require_file "$BANDIT_CONFIG_PATH"
  require_file "$GITLEAKS_IGNORE_PATH"

  print_tool_header \
    "Semgrep" \
    "Static pattern-based scanning for security and correctness issues." \
    "Combines community and repo custom rules across tracked source files." \
    "https://semgrep.dev/docs/"
  echo "▶ Running Semgrep"
  SEMGREP_HOME_DIR="${SEMGREP_HOME_DIR:-${REPORT_DIR}/.semgrep-home}"
  mkdir -p "$SEMGREP_HOME_DIR"
  semgrep_stderr_log="${REPORT_DIR}/semgrep.stderr.log"
  set +e
  HOME="$SEMGREP_HOME_DIR" semgrep scan \
    --config "p/security-audit" \
    --config "p/python" \
    --config "$SEMGREP_CONFIG_PATH" \
    --exclude "${VENV_NAME}" \
    --exclude ".venv" \
    --exclude "artifacts" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    . 2>"$semgrep_stderr_log"
  SEMGREP_EXIT=$?
  set -e
  if [[ "$SEMGREP_EXIT" -gt 1 ]]; then
    echo "⚠️  Semgrep remote config fetch failed; retrying with local config only (${SEMGREP_CONFIG_PATH})."
    set +e
    HOME="$SEMGREP_HOME_DIR" semgrep scan \
      --config "$SEMGREP_CONFIG_PATH" \
      --exclude "${VENV_NAME}" \
      --exclude ".venv" \
      --exclude "artifacts" \
      --json \
      --output "${REPORT_DIR}/semgrep.json" \
      . 2>>"$semgrep_stderr_log"
    SEMGREP_EXIT=$?
    set -e
  fi
  if [[ "$SEMGREP_EXIT" -gt 1 ]]; then
    echo "❌ Semgrep failed to execute."
    exit 1
  fi
  if [[ "$SEMGREP_EXIT" -eq 1 ]]; then
    echo "⚠️  Semgrep reported findings; continuing to centralized SAST gating."
  fi
  #R045: Emit detailed Semgrep status when output is unsuppressed.
  #R047: Keep Semgrep output unsuppressed by avoiding quiet-mode flags.
  semgrep_findings="$(count_report_findings "semgrep" "${REPORT_DIR}/semgrep.json")"
  echo "ℹ️  Semgrep detailed status: exit_code=${SEMGREP_EXIT}; findings=${semgrep_findings}; report=${REPORT_DIR}/semgrep.json; stderr_log=${semgrep_stderr_log}"
  print_semgrep_findings "${REPORT_DIR}/semgrep.json"

  print_tool_header \
    "Bandit" \
    "Static security analyzer for Python source code." \
    "Flags known insecure coding patterns and risky API usage." \
    "https://bandit.readthedocs.io/"
  echo "▶ Running Bandit"
  #R050: Autodiscover Python app targets: src/<package> dirs (excluding tooling `scripts` and Swift
  #R050: `macos-ui`), tests/py, and numbered root scripts. Matches teller's intent without scanning
  #R050: runner-owned tooling copies under src/scripts.
  bandit_targets=()
  if [[ -d ./src ]]; then
    for bandit_src_sub in ./src/*/; do
      bandit_src_base="$(basename "$bandit_src_sub")"
      [[ "$bandit_src_base" == "scripts" || "$bandit_src_base" == "macos-ui" ]] && continue
      [[ -n "$(find "$bandit_src_sub" -name '*.py' -print 2>/dev/null | head -n 1)" ]] && bandit_targets+=("${bandit_src_sub%/}")
    done
  fi
  [[ -d ./tests/py ]] && bandit_targets+=(./tests/py)
  shopt -s nullglob
  bandit_root_py=(./[0-9][0-9]_*.py)
  shopt -u nullglob
  [[ "${#bandit_root_py[@]}" -gt 0 ]] && bandit_targets+=("${bandit_root_py[@]}")
  # Distinguish scanner findings from scanner execution failures.
  if [[ "${#bandit_targets[@]}" -eq 0 ]]; then
    echo "ℹ️  Bandit skipped (no Python sources discovered)."
    printf '{"results":[]}\n' > "${REPORT_DIR}/bandit.json"
    BANDIT_EXIT=0
  else
    set +e
    bandit -r "${bandit_targets[@]}" -c "$BANDIT_CONFIG_PATH" -f json -o "${REPORT_DIR}/bandit.json"
    BANDIT_EXIT=$?
    set -e
  fi
  if [[ "$BANDIT_EXIT" -gt 1 ]]; then
    echo "❌ Bandit failed to execute."
    exit 1
  fi
  #R050: Emit detailed Bandit status when output is unsuppressed.
  bandit_findings="$(count_report_findings "bandit" "${REPORT_DIR}/bandit.json")"
  echo "ℹ️  Bandit detailed status: exit_code=${BANDIT_EXIT}; findings=${bandit_findings}; report=${REPORT_DIR}/bandit.json"

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
  #R055: Emit detailed pip-audit status when output is unsuppressed.
  pip_audit_findings="$(count_report_findings "pip-audit" "${REPORT_DIR}/pip-audit.json")"
  echo "ℹ️  pip-audit detailed status: exit_code=${PIP_AUDIT_EXIT}; vulnerabilities=${pip_audit_findings}; report=${REPORT_DIR}/pip-audit.json"

  print_tool_header \
    "detect-secrets" \
    "Scans repository files for high-entropy and known secret formats." \
    "Helps catch accidentally committed credentials before release." \
    "https://github.com/Yelp/detect-secrets"
  echo "▶ Running detect-secrets"
  set +e
  detect-secrets scan --all-files --force-use-all-plugins \
    --exclude-files "(^\.git/|^${VENV_NAME}/|^\.venv/|^artifacts/|^\.ruff_cache/|^\.pytest_cache/|^__pycache__/|^backups/|^archive/backup_extracts/|^README\.md\$|^config/bank_statements/|^config/security/binary-integrity-policy\.json\$|^tests/sh/99_restore_database\.bats\$|^src/macos-ui/\.derivedData-ui-tests/|^src/macos-ui/\.build/|^requirements/)" \
    > "${REPORT_DIR}/detect-secrets.json"
  DETECT_SECRETS_EXIT=$?
  set -e
  if [[ "$DETECT_SECRETS_EXIT" -ne 0 ]]; then
    echo "❌ detect-secrets failed to execute."
    exit 1
  fi
  #R060: Emit detailed detect-secrets status when output is unsuppressed.
  detect_secrets_findings="$(count_report_findings "detect-secrets" "${REPORT_DIR}/detect-secrets.json")"
  echo "ℹ️  detect-secrets detailed status: exit_code=${DETECT_SECRETS_EXIT}; findings=${detect_secrets_findings}; report=${REPORT_DIR}/detect-secrets.json"

  run_ruff_sast "${REPORT_DIR}/ruff.json"

  run_gitleaks_sast "${REPORT_DIR}/gitleaks.json"

  # Execute ShellCheck within SAST lane and feed severity counts into centralized gating.
  run_shellcheck_sast "${REPORT_DIR}/shellcheck.json"
  run_swift_sast "${REPORT_DIR}/swiftlint.json"

  # Produce consolidated SAST gate summary and enforce blocking policy.
  python3 "${SECURITY_RUNNER_HOME}/tests/py/security/sast_summary_gate.py"     "${REPORT_DIR}"     "${FAIL_ON_MEDIUM_OR_HIGHER}"     "medium"
  echo "✅ Static Application Security Testing (SAST) checks completed."
fi

if [[ "$RUN_DAST" == "true" ]]; then
  run_dast_checks "$REPORT_DIR"
fi

# Emit explicit completion status and artifact location for operators.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
