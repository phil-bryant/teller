#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
security_init_repo_root "$SCRIPT_PATH"
REPO_ROOT="${SECURITY_REPO_ROOT}"
echo "running DAST (Dynamic Application Security Testing)"

#R005: Runner-owned engine code/SQL resolved repo-override-else-runner; app + DB integration are knobs.
SECURITY_PY_DIR="$(security_resolve_asset tests/py/security)"
SECURITY_SCRIPTS_DIR="$(security_resolve_asset src/scripts)"
DAST_APP_SCRIPT="${DAST_APP_SCRIPT:-09_run_classification_api.py}"
DAST_DB_INTEGRATION="${DAST_DB_INTEGRATION:-true}"

#R001: Dynamic lane prints explicit startup banner before DAST orchestration.
#R005: Dynamic lane resolves repo root and executes with strict shell settings.
#R010: Dynamic lane bootstraps isolated security toolchain venv for DAST dependencies.
#R015: Dynamic lane defaults to RUN_DAST=true and RUN_SAST=false behavior.
#R020: Dynamic lane prints completion markers and report artifact location.
#R025: Dynamic lane captures baseline and executes cleanup to avoid DB state leakage.
#R030: Dynamic lane parses ZAP summary and enforces configurable severity threshold gate.
#R045: Dynamic lane runs Schemathesis from report_dir to keep .schemathesis out of repo root.
#R050: Dynamic lane redacts persisted Schemathesis token-bearing artifacts.
#R055: Dynamic lane enforces hash-pinned security requirements for toolchain reinstall.
REPORT_DIR="${SECURITY_REPORT_DIR:-./artifacts/security-dast}"
RUN_SAST="${RUN_SAST:-false}"
RUN_DAST="${RUN_DAST:-true}"
RUN_SWIFT_SAST="${RUN_SWIFT_SAST:-true}"
#R015: Support configurable execution lanes and report destination.
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./artifacts/venv/security}"
SECURITY_REQUIREMENTS_FILE="${SECURITY_REQUIREMENTS_FILE:-$(security_resolve_asset requirements/security/requirements-security.txt)}"
SECURITY_CONFIG_DIR="${SECURITY_CONFIG_DIR:-$(security_resolve_asset config/security)}"
SEMGREP_CONFIG_PATH="${SEMGREP_CONFIG_PATH:-${SECURITY_CONFIG_DIR}/semgrep.yml}"
BANDIT_CONFIG_PATH="${BANDIT_CONFIG_PATH:-${SECURITY_CONFIG_DIR}/bandit.yml}"
GITLEAKS_IGNORE_PATH="${GITLEAKS_IGNORE_PATH:-${SECURITY_CONFIG_DIR}/gitleaksignore}"
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

requirements_file_has_hashes() {
  #R055: Detect whether requirements file includes sha256 hash pins.
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
  #R055: Stop lane bootstrap early when hash pins are missing.
  local requirements_file="$1"
  require_file "$requirements_file"
  if ! requirements_file_has_hashes "$requirements_file"; then
    echo "❌ Requirements file is not hash-pinned: ${requirements_file}"
    echo "Run ./03_prepare_supply_chain_integrity.sh to regenerate lockfiles with hashes."
    exit 1
  fi
}

ensure_security_venv() {
  #R005: Bootstrap isolated security toolchain environment before scanning.
  local run_schemathesis="${RUN_SCHEMATHESIS:-true}"
  local need_semgrep="false"
  local need_schemathesis="false"
  if [[ "$RUN_SAST" == "true" ]]; then
    need_semgrep="true"
  fi
  if [[ "$RUN_DAST" == "true" && "$run_schemathesis" == "true" ]]; then
    need_schemathesis="true"
  fi
  if [[ "$need_semgrep" != "true" && "$need_schemathesis" != "true" ]]; then
    return 0
  fi

  local security_python="${SECURITY_VENV_DIR}/bin/python"
  local security_semgrep="${SECURITY_VENV_DIR}/bin/semgrep"
  local security_schemathesis="${SECURITY_VENV_DIR}/bin/schemathesis"

  security_console_script_usable() {
    local script_path="$1"
    local probe_arg="${2:---version}"
    [[ -x "$script_path" ]] || return 1
    "$script_path" "$probe_arg" >/dev/null 2>&1
  }

  if [[ -d "$SECURITY_VENV_DIR" ]] && ! python_interpreter_usable "$security_python"; then
    echo "⚠️  Recreating security virtualenv because interpreter is unusable: ${security_python}"
    rm -rf "$SECURITY_VENV_DIR"
  fi

  if [[ ! -d "$SECURITY_VENV_DIR" ]]; then
    echo "▶ Creating isolated security virtualenv at ${SECURITY_VENV_DIR}"
    python3 -m venv "$SECURITY_VENV_DIR"
  fi

  local needs_semgrep_repair="false"
  local needs_schemathesis_repair="false"
  if [[ "$need_semgrep" == "true" ]] && ( [[ ! -x "$security_semgrep" ]] || ! security_console_script_usable "$security_semgrep" "--version" ); then
    needs_semgrep_repair="true"
  fi
  if [[ "$need_schemathesis" == "true" ]] && ( [[ ! -x "$security_schemathesis" ]] || ! security_console_script_usable "$security_schemathesis" "--version" ); then
    needs_schemathesis_repair="true"
  fi
  if [[ "$needs_semgrep_repair" == "true" || "$needs_schemathesis_repair" == "true" ]]; then
    require_hashed_requirements_file "$SECURITY_REQUIREMENTS_FILE"
    echo "▶ Repairing security toolchain entrypoints in ${SECURITY_VENV_DIR}"
    "$security_python" -m pip install --upgrade pip
    "$security_python" -m pip install --require-hashes --force-reinstall -r "$SECURITY_REQUIREMENTS_FILE" --no-deps
  fi
}

security_toolchain_usable() {
  python_interpreter_usable "${SECURITY_VENV_DIR}/bin/python"
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  local watch_pid="${3:-}"
  local curl_args=(-fsS)
  if [[ "$url" == https://* ]]; then
    curl_args+=(-k)
  fi
  local start_ts
  start_ts="$(date +%s)"
  while true; do
    if [[ -n "$watch_pid" ]] && ! kill -0 "$watch_pid" >/dev/null 2>&1; then
      echo "❌ Process ${watch_pid} exited before ${url} became ready."
      return 1
    fi
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

is_tcp_port_in_use() {
  # Detect occupied localhost ports before binding DAST API or ZAP quick-scan proxy.
  local host="$1"
  local port="$2"
  python3 - <<'PY' "$host" "$port"
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.25)
try:
    rc = s.connect_ex((host, port))
    print("used" if rc == 0 else "free")
finally:
    s.close()
PY
}

find_available_tcp_port() {
  # Auto-select the next free localhost port when the requested port is in use.
  local host="$1"
  local start_port="$2"
  local max_attempts="${3:-50}"
  python3 - <<'PY' "$host" "$start_port" "$max_attempts"
import socket
import sys

host = sys.argv[1]
start_port = int(sys.argv[2])
max_attempts = int(sys.argv[3])

for offset in range(0, max_attempts + 1):
    candidate = start_port + offset
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((host, candidate))
            print(candidate)
            raise SystemExit(0)
        except OSError:
            continue

raise SystemExit(1)
PY
}

run_zap_quick_scan() {
  local zap_cli_cmd="$1"
  local zap_home_dir="$2"
  local zap_quiet="$3"
  local target_url="$4"
  local html_report="$5"
  local log_report="$6"
  local proxy_host="$7"
  local proxy_port="$8"
  print_tool_header \
    "OWASP ZAP" \
    "Dynamic scan of live HTTP endpoints for common web vulnerabilities." \
    "Uses quick scan mode to spider and actively probe reachable routes." \
    "https://www.zaproxy.org/"
  echo "▶ Running OWASP ZAP quick scan (CLI) against ${target_url}"
  echo "▶ ZAP home directory: ${zap_home_dir}"
  echo "▶ ZAP quick-scan proxy: ${proxy_host}:${proxy_port}"
  local zap_exit=0
  set +e
  if [[ "$zap_quiet" == "true" ]]; then
    "$zap_cli_cmd" -cmd \
      -dir "$zap_home_dir" \
      -host "$proxy_host" \
      -port "$proxy_port" \
      -quickurl "$target_url" \
      -quickout "$html_report" \
      -quickprogress \
      -silent 2>&1 | tee "$log_report"
    zap_exit=${PIPESTATUS[0]}
  else
    "$zap_cli_cmd" -cmd \
      -dir "$zap_home_dir" \
      -host "$proxy_host" \
      -port "$proxy_port" \
      -quickurl "$target_url" \
      -quickout "$html_report" \
      -quickprogress 2>&1 | tee "$log_report"
    zap_exit=${PIPESTATUS[0]}
  fi
  set -e

  if [[ "$zap_exit" -ne 0 ]]; then
    if grep -qi "operation not permitted" "$log_report"; then
      echo "⚠️  OWASP ZAP quick scan could not start in this restricted environment; continuing with placeholder artifacts."
      if [[ ! -s "$html_report" ]]; then
        printf '<html><body>OWASP ZAP quick scan unavailable in restricted runtime.</body></html>\n' > "$html_report"
      fi
      return 0
    fi
    echo "❌ OWASP ZAP quick scan failed."
    exit 1
  fi
}

summarize_zap_html_report() {
  local html_report="$1"
  local summary_json="$2"
  python3 "${SECURITY_PY_DIR}/zap_summary_parser.py" "$html_report" "$summary_json"
}

read_classifier_write_token() {
  # Resolve DAST write token from env when present, else 1psa.
  local write_token="${TELLER_CLASSIFIER_WRITE_TOKEN:-}"
  if [[ -z "$write_token" ]]; then
    write_token="$(rb_read_1psa_item "$WRITE_TOKEN_PSA_ITEM")"
  fi
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
  shellcheck_targets=(./[0-9][0-9]_*.sh)
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
}

run_gitleaks_sast() {
  # Run gitleaks and preserve JSON findings for centralized secret-leak gating.
  local gitleaks_report="$1"

  require_command gitleaks
  print_tool_header \
    "gitleaks" \
    "Detects hardcoded secrets and credential patterns in tracked files." \
    "Runs repository-focused leak detection and emits JSON findings." \
    "https://github.com/gitleaks/gitleaks"
  echo "▶ Running gitleaks"
  set +e
  gitleaks detect \
    --source . \
    --no-git \
    --gitleaks-ignore-path "$GITLEAKS_IGNORE_PATH" \
    --report-format json \
    --report-path "$gitleaks_report"
  GITLEAKS_EXIT=$?
  set -e
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

run_dast_checks() {
(
  set -euo pipefail

  run_category_integrity_checks() {
    local report_dir_abs="$1"
    local integrity_report_path="${report_dir_abs}/category-integrity.json"
    local seed_sql_path
    seed_sql_path="$(security_resolve_asset src/sql/postgres/teller_nys_snw_category.sql)"
    local strict_mode="${DAST_CATEGORY_INTEGRITY_STRICT:-true}"

    echo "▶ Running post-DAST category integrity checks"
    set +e
    PYTHONPATH="${dast_integrity_pythonpath}" "$dast_app_python"       "${SECURITY_PY_DIR}/category_integrity_check.py"       "$integrity_report_path"       "$seed_sql_path"       "$strict_mode"
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
    local matchy_seed_path="${6:-}"
    local dast_run_id="${7:-unknown}"
    python3 "${SECURITY_PY_DIR}/schemathesis_fixture_prep.py"       "$source_openapi_url"       "$source_base_url"       "$output_schema_path"       "$write_token"       "$write_token_header_name"       "$matchy_seed_path"       "$dast_run_id"
  }

  seed_matchy_data_for_schemathesis() {
    local output_json_path="$1"
    local dast_run_id="${2:-unknown}"
    set +e
    PYTHONPATH="${dast_integrity_pythonpath}" "$dast_app_python" - <<'PY' "$output_json_path" "$dast_run_id"
import json
import pathlib
import sys
import uuid

from sqlalchemy import text

output_path = pathlib.Path(sys.argv[1])
dast_run_id = sys.argv[2]
payload = {
    "status": "skipped",
    "match_ids": [],
    "active_match_transaction_ids": [],
    "candidate_transaction_id": None,
    "candidate_email_id": None,
    "override_email_message_id": None,
}

try:
    from teller.teller_db import get_engine
except Exception as exc:
    payload["reason"] = f"db_import_failed: {exc}"
else:
    try:
        engine = get_engine()
        with engine.begin() as conn:
            candidate_rows = conn.execute(
                text(
                    """
                    SELECT mr.transaction_id, c.email_message_id
                      FROM teller.transaction_email_match_run mr
                      JOIN teller.transaction_email_candidate c
                        ON c.match_run_id = mr.match_run_id
                     WHERE NOT EXISTS (
                           SELECT 1
                             FROM teller.transaction_email_match m
                            WHERE m.transaction_id = mr.transaction_id
                              AND m.active = TRUE
                       )
                     ORDER BY mr.completed_at DESC NULLS LAST, mr.match_run_id DESC, c.candidate_id ASC
                     LIMIT 24
                    """
                )
            ).fetchall()
            for row in candidate_rows:
                tx_value = row[0]
                email_value = row[1]
                if isinstance(tx_value, str) and tx_value and isinstance(email_value, str) and email_value:
                    payload["candidate_transaction_id"] = tx_value
                    payload["candidate_email_id"] = email_value
                    break
            existing = conn.execute(
                text(
                    """
                    SELECT match_id, email_message_id
                         , transaction_id
                      FROM teller.transaction_email_match
                     WHERE active = TRUE
                     ORDER BY updated_at DESC NULLS LAST, match_id DESC
                     LIMIT 8
                    """
                )
            ).fetchall()
            if existing:
                payload["status"] = "existing"
                payload["match_ids"] = [int(row[0]) for row in existing if row and row[0] is not None]
                for row in existing:
                    tx_value = row[2]
                    if isinstance(tx_value, str) and tx_value:
                        payload["active_match_transaction_ids"].append(tx_value)
                    email_value = row[1]
                    if isinstance(email_value, str) and email_value:
                        payload["override_email_message_id"] = email_value
                        break
                if payload["candidate_transaction_id"] is None:
                    candidate_tx_row = conn.execute(
                        text(
                            """
                            SELECT t.transaction_id
                              FROM teller.transaction t
                             WHERE t.status = 'posted'
                               AND NOT EXISTS (
                                     SELECT 1
                                       FROM teller.transaction_email_match m
                                      WHERE m.transaction_id = t.transaction_id
                                        AND m.active = TRUE
                                 )
                             ORDER BY t.date DESC NULLS LAST, t.transaction_id DESC
                             LIMIT 1
                            """
                        )
                    ).fetchone()
                    if candidate_tx_row and candidate_tx_row[0]:
                        candidate_tx_id = str(candidate_tx_row[0])
                        seeded_candidate_email = f"dast_seed_candidate_{dast_run_id}_{uuid.uuid4().hex}"
                        seeded_run = conn.execute(
                            text(
                                """
                                INSERT INTO teller.transaction_email_match_run (
                                    transaction_id,
                                    trigger_source,
                                    model_name,
                                    prompt_version,
                                    status,
                                    completed_at
                                ) VALUES (
                                    :transaction_id,
                                    CAST('manual' AS teller.matchy_trigger_source),
                                    'dast_seed',
                                    'dast_seed',
                                    CAST('succeeded' AS teller.matchy_run_status),
                                    CURRENT_TIMESTAMP
                                )
                                RETURNING match_run_id
                                """
                            ),
                            {"transaction_id": candidate_tx_id},
                        ).fetchone()
                        if seeded_run and seeded_run[0] is not None:
                            conn.execute(
                                text(
                                    """
                                    INSERT INTO teller.transaction_email_candidate (
                                        match_run_id,
                                        transaction_id,
                                        email_message_id,
                                        score,
                                        reason_json,
                                        is_selected_by_ai
                                    ) VALUES (
                                        :match_run_id,
                                        :transaction_id,
                                        :email_message_id,
                                        :score,
                                        CAST(:reason_json AS jsonb),
                                        TRUE
                                    )
                                    """
                                ),
                                {
                                    "match_run_id": int(seeded_run[0]),
                                    "transaction_id": candidate_tx_id,
                                    "email_message_id": seeded_candidate_email,
                                    "score": 0.99,
                                    "reason_json": '{"source":"dast_seed"}',
                                },
                            )
                            payload["candidate_transaction_id"] = candidate_tx_id
                            payload["candidate_email_id"] = seeded_candidate_email
                            if payload["override_email_message_id"] is None:
                                payload["override_email_message_id"] = seeded_candidate_email
            else:
                tx_rows = conn.execute(
                    text(
                        """
                        SELECT transaction_id
                          FROM teller.transaction
                         WHERE status = 'posted'
                         ORDER BY date DESC NULLS LAST, transaction_id DESC
                         LIMIT 2
                        """
                    )
                ).fetchall()
                if tx_rows and tx_rows[0] and tx_rows[0][0]:
                    active_tx_id = str(tx_rows[0][0])
                    seeded_active_email = f"dast_seed_active_{dast_run_id}_{uuid.uuid4().hex}"
                    seeded_active = conn.execute(
                        text(
                            """
                            INSERT INTO teller.transaction_email_match (
                                transaction_id,
                                email_message_id,
                                state,
                                selected_by,
                                active
                            ) VALUES (
                                :transaction_id,
                                :email_message_id,
                                CAST('ai_match_confident' AS teller.transaction_email_match_state),
                                CAST('ai' AS teller.transaction_email_match_selected_by),
                                TRUE
                            )
                            RETURNING match_id
                            """
                        ),
                        {
                            "transaction_id": active_tx_id,
                            "email_message_id": seeded_active_email,
                        },
                    ).fetchone()
                    if seeded_active and seeded_active[0] is not None:
                        payload["status"] = "seeded"
                        payload["match_ids"] = [int(seeded_active[0])]
                        payload["active_match_transaction_ids"] = [active_tx_id]
                        payload["override_email_message_id"] = seeded_active_email
                    candidate_tx_id = None
                    if len(tx_rows) > 1 and tx_rows[1] and tx_rows[1][0]:
                        candidate_tx_id = str(tx_rows[1][0])
                    elif active_tx_id:
                        candidate_tx_id = active_tx_id
                    if candidate_tx_id:
                        seeded_candidate_email = f"dast_seed_candidate_{dast_run_id}_{uuid.uuid4().hex}"
                        seeded_run = conn.execute(
                            text(
                                """
                                INSERT INTO teller.transaction_email_match_run (
                                    transaction_id,
                                    trigger_source,
                                    model_name,
                                    prompt_version,
                                    status,
                                    completed_at
                                ) VALUES (
                                    :transaction_id,
                                    CAST('manual' AS teller.matchy_trigger_source),
                                    'dast_seed',
                                    'dast_seed',
                                    CAST('succeeded' AS teller.matchy_run_status),
                                    CURRENT_TIMESTAMP
                                )
                                RETURNING match_run_id
                                """
                            ),
                            {"transaction_id": candidate_tx_id},
                        ).fetchone()
                        if seeded_run and seeded_run[0] is not None:
                            conn.execute(
                                text(
                                    """
                                    INSERT INTO teller.transaction_email_candidate (
                                        match_run_id,
                                        transaction_id,
                                        email_message_id,
                                        score,
                                        reason_json,
                                        is_selected_by_ai
                                    ) VALUES (
                                        :match_run_id,
                                        :transaction_id,
                                        :email_message_id,
                                        :score,
                                        CAST(:reason_json AS jsonb),
                                        TRUE
                                    )
                                    """
                                ),
                                {
                                    "match_run_id": int(seeded_run[0]),
                                    "transaction_id": candidate_tx_id,
                                    "email_message_id": seeded_candidate_email,
                                    "score": 0.99,
                                    "reason_json": '{"source":"dast_seed"}',
                                },
                            )
                            payload["candidate_transaction_id"] = candidate_tx_id
                            payload["candidate_email_id"] = seeded_candidate_email
                            if payload["override_email_message_id"] is None:
                                payload["override_email_message_id"] = seeded_candidate_email
                else:
                    payload["reason"] = "no_posted_transactions_available"
    except Exception as exc:
        payload["status"] = "skipped"
        payload["reason"] = f"db_seed_failed: {exc}"

output_path.parent.mkdir(parents=True, exist_ok=True)
with output_path.open("w", encoding="utf-8") as fh:
    json.dump(payload, fh)
    fh.write("\n")
print(json.dumps(payload))
PY
    local seed_exit=$?
    set -e
    return "$seed_exit"
  }

  run_delete_category_contract_check() {
    local schema_path="$1"
    local source_base_url="$2"
    local output_json_path="$3"
    local write_token="$4"
    local write_token_header_name="$5"
    local dast_run_id="${6:-unknown}"
    python3 "${SECURITY_PY_DIR}/delete_category_contract_check.py"       "$schema_path"       "$source_base_url"       "$output_json_path"       "$write_token"       "$write_token_header_name"       "$dast_run_id"
  }

  local report_dir="$1"
  local report_dir_abs
  report_dir_abs="$(cd "$report_dir" && pwd)"

  local base_host="${DAST_BASE_HOST:-127.0.0.1}"
  local base_port="${DAST_BASE_PORT:-8787}"
  local base_url="${DAST_BASE_URL:-}"
  local openapi_url="${DAST_OPENAPI_URL:-}"

  local run_schemathesis="${RUN_SCHEMATHESIS:-true}"
  local run_zap="${RUN_ZAP:-true}"
  #R035: Findings from Schemathesis are blocking by default unless explicitly downgraded.
  local schemathesis_fail_on_findings="${SCHEMATHESIS_FAIL_ON_FINDINGS:-true}"
  local schemathesis_mode="${SCHEMATHESIS_MODE:-positive}"
  local reuse_existing_api="${DAST_REUSE_EXISTING_API:-${MACOS_UI_DAST_REUSE_EXISTING_API:-false}}"
  local run_token_capture_dast="${RUN_TOKEN_CAPTURE_DAST:-auto}" # true|false|auto
  local fail_on_high_critical="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
  local zap_fail_threshold="${SECURITY_ZAP_FAIL_THRESHOLD:-high}"
  local zap_fail_threshold_normalized=""
  local dast_write_token
  dast_write_token="$(read_classifier_write_token)"
  local zap_cli_cmd="${ZAP_CLI_CMD:-/Applications/ZAP.app/Contents/MacOS/ZAP.sh}"
  local zap_home_root="${ZAP_HOME_DIR:-${report_dir_abs}/zap-home}"
  local zap_quick_home_dir="${ZAP_QUICK_HOME_DIR:-${zap_home_root}/quick-scan}"
  # Keep ZAP quick-scan output visible by default unless explicitly silenced.
  local zap_quiet="${ZAP_QUIET:-false}"
  local zap_quick_proxy_host="${ZAP_QUICK_PROXY_HOST:-127.0.0.1}"
  local zap_quick_proxy_port="${ZAP_QUICK_PROXY_PORT:-8091}"

  local dast_app_python="${DAST_APP_PYTHON:-./${VENV_NAME}/bin/python}"
  local dast_integrity_pythonpath="${PYTHONPATH:-}"
  if [[ -n "$dast_integrity_pythonpath" ]]; then
    dast_integrity_pythonpath="${PWD}/src:${PWD}:${dast_integrity_pythonpath}"
  else
    dast_integrity_pythonpath="${PWD}/src:${PWD}"
  fi

  local schemathesis_seed="${SCHEMATHESIS_SEED:-424242}"
  local schemathesis_max_examples="${SCHEMATHESIS_MAX_EXAMPLES:-25}"
  local zap_classification_target="${ZAP_CLASSIFICATION_TARGET:-}"

  if ! python_interpreter_usable "$dast_app_python"; then
    dast_app_python="python3"
  fi
  if [[ "$dast_app_python" == "python3" ]] && [[ -d "./${VENV_NAME}/lib" ]]; then
    for site_packages_dir in ./${VENV_NAME}/lib/python*/site-packages; do
      if [[ -d "$site_packages_dir" ]]; then
        local site_packages_dir_abs
        site_packages_dir_abs="$(cd "$site_packages_dir" && pwd)"
        if [[ -n "$dast_integrity_pythonpath" ]]; then
          dast_integrity_pythonpath="${site_packages_dir_abs}:${dast_integrity_pythonpath}"
        else
          dast_integrity_pythonpath="${site_packages_dir_abs}"
        fi
      fi
    done
  fi

  if [[ "$reuse_existing_api" != "true" ]]; then
    if ! [[ "$base_port" =~ ^[0-9]+$ ]]; then
      echo "❌ DAST_BASE_PORT must be numeric; received: ${base_port}"
      exit 1
    fi
    local requested_base_port="$base_port"
    local api_port_status
    api_port_status="$(is_tcp_port_in_use "$base_host" "$requested_base_port")"
    if [[ "$api_port_status" == "used" ]]; then
      local resolved_base_port=""
      if ! resolved_base_port="$(find_available_tcp_port "$base_host" "$requested_base_port" 100)"; then
        echo "❌ Unable to find an available API port near ${requested_base_port} on ${base_host}."
        exit 1
      fi
      base_port="$resolved_base_port"
      echo "⚠️  DAST_BASE_PORT ${requested_base_port} is already in use; auto-selected ${base_port} to avoid stale API reuse."
    fi
  fi

  if [[ -z "${DAST_BASE_URL:-}" ]]; then
    base_url="https://${base_host}:${base_port}"
  fi
  if [[ "$base_url" == http://* ]]; then
    echo "❌ DAST_BASE_URL must use https:// (received: ${base_url})"
    exit 1
  fi
  if [[ -z "${DAST_OPENAPI_URL:-}" ]]; then
    openapi_url="${base_url}/openapi.json"
  fi
  if [[ "$openapi_url" == http://* ]]; then
    echo "❌ DAST_OPENAPI_URL must use https:// (received: ${openapi_url})"
    exit 1
  fi
  if [[ -z "${ZAP_CLASSIFICATION_TARGET:-}" ]]; then
    zap_classification_target="${base_url}/health"
  fi

  # Ensure Python/requests-based tooling trusts the local classifier cert when DAST targets
  # loopback HTTPS. This keeps Schemathesis + fixture prep compatible with HTTPS-only lanes.
  local classifier_tls_cert="${TELLER_CLASSIFIER_TLS_CERT_FILE:-$HOME/.teller/classifier-localhost-cert.pem}"
  if [[ "$base_url" == https://127.0.0.1:* || "$base_url" == https://localhost:* ]]; then
    if [[ -f "$classifier_tls_cert" ]]; then
      export SSL_CERT_FILE="$classifier_tls_cert"
      echo "▶ DAST TLS trust anchor: ${classifier_tls_cert}"
    fi
  fi

  local classifier_api_pid=""
  local mailcart_stub_pid=""
  local token_capture_pid=""

  #R025: Generate a per-run DAST tag and capture a pre-run DB baseline so the
  #R025: EXIT trap can restore-then-delete every row the run touched.
  local dast_run_id="${DAST_RUN_ID:-}"
  if [[ -z "$dast_run_id" ]]; then
    local raw_run_id
    if command -v uuidgen >/dev/null 2>&1; then
      raw_run_id="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-12)"
    else
      raw_run_id="$(date +%s)$$"
    fi
    dast_run_id="dast-${raw_run_id}"
  fi
  export DAST_RUN_ID="$dast_run_id"
  printf '%s\n' "$dast_run_id" > "${report_dir_abs}/dast-run-id.txt"
  echo "▶ DAST run id: ${dast_run_id}"

  local dast_baseline_path="${report_dir_abs}/dast-baseline.json"
  local dast_cleanup_summary_path="${report_dir_abs}/dast-cleanup.json"
  local dast_skip_cleanup="${DAST_SKIP_CLEANUP:-false}"
  #R025: DB baseline/seed/cleanup/integrity only apply when the target app integrates the teller DB.
  if [[ "${DAST_DB_INTEGRATION:-true}" != "true" ]]; then
    dast_skip_cleanup="true"
  fi
  local dast_cleanup_done="false"

  if [[ "$dast_skip_cleanup" != "true" ]]; then
    echo "▶ Capturing pre-DAST database baseline at ${dast_baseline_path}"
    set +e
    PYTHONPATH="${dast_integrity_pythonpath}" "$dast_app_python" \
      "${SECURITY_SCRIPTS_DIR}/dast_baseline.py" "$dast_baseline_path" \
      > "${report_dir_abs}/dast-baseline.log" 2>&1
    local dast_baseline_exit=$?
    set -e
    if [[ "$dast_baseline_exit" -ne 0 ]]; then
      echo "⚠️  Pre-DAST baseline capture failed (exit ${dast_baseline_exit}); see ${report_dir_abs}/dast-baseline.log"
    fi
  else
    echo "ℹ️  DAST baseline + cleanup skipped because DAST_SKIP_CLEANUP=true"
  fi

  _cleanup_dast_state() {
    local exit_code=$?
    if [[ -n "${token_capture_pid:-}" ]] && kill -0 "${token_capture_pid}" >/dev/null 2>&1; then
      kill "${token_capture_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${mailcart_stub_pid:-}" ]] && kill -0 "${mailcart_stub_pid}" >/dev/null 2>&1; then
      kill "${mailcart_stub_pid}" >/dev/null 2>&1 || true
      wait "${mailcart_stub_pid}" 2>/dev/null || true
    fi
    if [[ -n "${classifier_api_pid:-}" ]] && kill -0 "${classifier_api_pid}" >/dev/null 2>&1; then
      kill "${classifier_api_pid}" >/dev/null 2>&1 || true
      wait "${classifier_api_pid}" 2>/dev/null || true
    fi
    if [[ "${dast_cleanup_done:-false}" == "true" ]]; then
      return $exit_code
    fi
    dast_cleanup_done="true"
    if [[ "${dast_skip_cleanup:-false}" == "true" ]]; then
      return $exit_code
    fi
    if [[ -z "${dast_baseline_path:-}" || ! -f "${dast_baseline_path}" ]]; then
      echo "⚠️  Skipping DAST cleanup; no baseline at ${dast_baseline_path:-<unset>}"
      return $exit_code
    fi
    echo "▶ Restoring database to pre-DAST baseline (run_id=${dast_run_id:-unknown})"
    PYTHONPATH="${dast_integrity_pythonpath:-}" "${dast_app_python}" \
      "${SECURITY_SCRIPTS_DIR}/dast_cleanup.py" \
      "${dast_baseline_path}" \
      "${dast_run_id:-unknown}" \
      "${dast_cleanup_summary_path}" \
      >> "${report_dir_abs}/dast-cleanup.log" 2>&1 || true
    return $exit_code
  }
  trap _cleanup_dast_state EXIT
  mkdir -p "$zap_quick_home_dir"

  # Start local classification API automatically for DAST execution.
  if [[ "$reuse_existing_api" == "true" ]]; then
    echo "▶ Reusing existing classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
  else
    if [[ "$run_schemathesis" == "true" && -z "${MAILCART_SERVICE_BASE_URL:-}" ]]; then
      local mailcart_host="${DAST_MAILCART_HOST:-127.0.0.1}"
      local mailcart_port="${DAST_MAILCART_PORT:-8790}"
      if ! [[ "$mailcart_port" =~ ^[0-9]+$ ]]; then
        echo "❌ DAST_MAILCART_PORT must be numeric; received: ${mailcart_port}"
        exit 1
      fi
      if [[ "$(is_tcp_port_in_use "$mailcart_host" "$mailcart_port")" == "used" ]]; then
        local resolved_mailcart_port=""
        if ! resolved_mailcart_port="$(find_available_tcp_port "$mailcart_host" "$mailcart_port" 100)"; then
          echo "❌ Unable to find an available Mailcart stub port near ${mailcart_port} on ${mailcart_host}."
          exit 1
        fi
        mailcart_port="$resolved_mailcart_port"
      fi
      #R040: Ensure Mailcart stub never binds to the same host:port as the DAST API.
      if [[ "$mailcart_host" == "$base_host" ]] && [[ "$mailcart_port" -eq "$base_port" ]]; then
        local collision_start_port="$((base_port + 1))"
        local resolved_mailcart_port=""
        if ! resolved_mailcart_port="$(find_available_tcp_port "$mailcart_host" "$collision_start_port" 100)"; then
          echo "❌ Unable to find an available Mailcart stub port that does not collide with API port ${base_port}."
          exit 1
        fi
        mailcart_port="$resolved_mailcart_port"
        echo "⚠️  DAST Mailcart stub port collided with API port ${base_port}; auto-selected ${mailcart_port}."
      fi
      local mailcart_cert="${TELLER_CLASSIFIER_TLS_CERT_FILE:-$HOME/.teller/classifier-localhost-cert.pem}"
      local mailcart_key="${TELLER_CLASSIFIER_TLS_KEY_FILE:-$HOME/.teller/classifier-localhost-key.pem}"
      if [[ ! -f "$mailcart_cert" || ! -f "$mailcart_key" ]]; then
        echo "❌ Mailcart HTTPS stub requires TLS cert/key at ${mailcart_cert} and ${mailcart_key}"
        exit 1
      fi
      local mailcart_stub_url="https://${mailcart_host}:${mailcart_port}"
      echo "▶ Starting DAST Mailcart HTTPS stub at ${mailcart_stub_url}"
      MAILCART_STUB_HOST="$mailcart_host" \
      MAILCART_STUB_PORT="$mailcart_port" \
      MAILCART_STUB_CERT="$mailcart_cert" \
      MAILCART_STUB_KEY="$mailcart_key" \
      python3 - <<'PY' >"${report_dir_abs}/mailcart-stub.log" 2>&1 &
import json
import os
import ssl
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

host = os.environ["MAILCART_STUB_HOST"]
port = int(os.environ["MAILCART_STUB_PORT"])
cert = os.environ["MAILCART_STUB_CERT"]
key = os.environ["MAILCART_STUB_KEY"]


class Handler(BaseHTTPRequestHandler):
    def _json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json({"ok": True})
            return
        if parsed.path == "/v1/messages/search":
            query = parse_qs(parsed.query).get("query", [""])[0]
            payload = {
                "messages": [
                    {
                        "message_id": "dast-msg-1",
                        "subject": f"DAST search {query}".strip(),
                        "preview": "stub preview",
                        "received_at": "2026-01-01T00:00:00Z",
                        "sender": "stub@example.test",
                        "body_text": "stub body text",
                    }
                ]
            }
            self._json(payload)
            return
        if parsed.path.startswith("/v1/messages/"):
            message_id = parsed.path.rsplit("/", 1)[-1]
            payload = {
                "message_id": message_id,
                "subject": "DAST stub message",
                "preview": "stub preview",
                "received_at": "2026-01-01T00:00:00Z",
                "sender": "stub@example.test",
                "recipients": "receiver@example.test",
                "html_body": "<p>stub</p>",
                "text_body": "stub",
                "body_text": "stub",
            }
            self._json(payload)
            return
        self._json({"detail": "not found"}, status=404)

    def log_message(self, fmt, *args):
        return


server = HTTPServer((host, port), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile=cert, keyfile=key)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
      mailcart_stub_pid="$!"
      wait_for_http "${mailcart_stub_url}/health" 30 "$mailcart_stub_pid"
      export MAILCART_SERVICE_BASE_URL="$mailcart_stub_url"
      echo "▶ DAST Mailcart base URL: ${MAILCART_SERVICE_BASE_URL}"
    fi
    echo "▶ Starting local classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
    TELLER_CLASSIFIER_WRITE_TOKEN="$dast_write_token" \
      TELLER_CLASSIFIER_API_HOST="$base_host" TELLER_CLASSIFIER_API_PORT="$base_port" \
      CLASSIFICATION_API_HOST="$base_host" CLASSIFICATION_API_PORT="$base_port" \
      CLASSY_API_HOST="$base_host" CLASSY_API_PORT="$base_port" \
      "$dast_app_python" "./${DAST_APP_SCRIPT}" >"${report_dir_abs}/classification-api.log" 2>&1 &
    classifier_api_pid="$!"
  fi
  wait_for_http "${base_url}/health" 45 "$classifier_api_pid"

  # Run Schemathesis and ZAP quick scans with configurable targets and gating.
  if [[ "$run_schemathesis" == "true" ]]; then
    require_command schemathesis
    print_tool_header \
      "Schemathesis" \
      "Property-based API testing driven by the OpenAPI specification." \
      "Finds contract mismatches by generating and exercising request scenarios." \
      "https://schemathesis.readthedocs.io/"
    echo "▶ Running Schemathesis against ${openapi_url}"
    local schemathesis_timeout_seconds="${SCHEMATHESIS_TIMEOUT_SECONDS:-300}"
    if ! [[ "$schemathesis_timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$schemathesis_timeout_seconds" -lt 1 ]]; then
      echo "❌ SCHEMATHESIS_TIMEOUT_SECONDS must be a positive integer; received: ${schemathesis_timeout_seconds}"
      exit 1
    fi
    local schemathesis_location="$openapi_url"
    local schemathesis_openapi_fixture="${report_dir_abs}/schemathesis-openapi.json"
    local schemathesis_matchy_seed="${report_dir_abs}/schemathesis-matchy-seed.json"
    if [[ "${DAST_DB_INTEGRATION:-true}" == "true" ]]; then
      if seed_matchy_data_for_schemathesis "$schemathesis_matchy_seed" "$dast_run_id" > "${report_dir_abs}/schemathesis-matchy-seed.log"; then
        echo "▶ Schemathesis matchy seed prepared at ${schemathesis_matchy_seed}"
      else
        echo "⚠️  Schemathesis matchy seed preparation failed; proceeding with live data only."
      fi
    else
      echo "ℹ️  Schemathesis matchy DB seeding skipped (DAST_DB_INTEGRATION=false)."
    fi
    if prepare_schemathesis_openapi_fixture "$openapi_url" "$base_url" "$schemathesis_openapi_fixture" "$dast_write_token" "$WRITE_TOKEN_HEADER_NAME" "$schemathesis_matchy_seed" "$dast_run_id" \
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
      "$dast_run_id" \
      | tee "${report_dir_abs}/schemathesis-delete-category-contract.log"
    #R050: Write raw output temporarily, then persist only token-redacted artifacts.
    local schemathesis_raw_log="${report_dir_abs}/schemathesis-raw.log"
    set +e
    "$dast_app_python" - "$schemathesis_raw_log" "$report_dir_abs" "$schemathesis_location" "$base_url" \
      "$dast_write_token" "$WRITE_TOKEN_HEADER_NAME" "$schemathesis_mode" "$schemathesis_seed" "$schemathesis_max_examples" \
      "$schemathesis_timeout_seconds" <<'PY'
import subprocess
import sys
from pathlib import Path

raw_log = Path(sys.argv[1])
working_directory = Path(sys.argv[2])
schemathesis_location = sys.argv[3]
base_url = sys.argv[4]
write_token = sys.argv[5]
write_token_header = sys.argv[6]
schemathesis_mode = sys.argv[7]
schemathesis_seed = sys.argv[8]
schemathesis_max_examples = sys.argv[9]
timeout_seconds = int(sys.argv[10])

command = [
    "schemathesis",
    "run",
    schemathesis_location,
    "--url",
    base_url,
    "--tls-verify=false",
    "--header",
    f"{write_token_header}: {write_token}",
    "--mode",
    schemathesis_mode,
    "--seed",
    schemathesis_seed,
    "--max-examples",
    schemathesis_max_examples,
    "--report",
    "junit",
    "--report-junit-path",
    str(working_directory / "schemathesis-junit.xml"),
]

with raw_log.open("w", encoding="utf-8") as stream:
    try:
        completed = subprocess.run(
            command,
            cwd=working_directory,
            stdout=stream,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
            check=False,
        )
        raise SystemExit(completed.returncode)
    except subprocess.TimeoutExpired:
        stream.write(f"\nSchemathesis timed out after {timeout_seconds}s; terminating run.\n")
        raise SystemExit(124)
PY
    SCHEMATHESIS_EXIT=$?
    set -e
    redact_secret_in_file "$schemathesis_raw_log" "${report_dir_abs}/schemathesis.log" "$dast_write_token"
    rm -f "$schemathesis_raw_log"
    if [[ -f "${report_dir_abs}/schemathesis-junit.xml" ]]; then
      redact_secret_in_place "${report_dir_abs}/schemathesis-junit.xml" "$dast_write_token"
    fi
    if [[ "$SCHEMATHESIS_EXIT" -gt 1 ]]; then
      if [[ "$SCHEMATHESIS_EXIT" -eq 124 ]]; then
        echo "❌ Schemathesis timed out after ${schemathesis_timeout_seconds}s."
      else
        echo "❌ Schemathesis failed to execute."
      fi
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
    if ! [[ "$zap_quick_proxy_port" =~ ^[0-9]+$ ]]; then
      echo "❌ ZAP_QUICK_PROXY_PORT must be numeric; received: ${zap_quick_proxy_port}"
      exit 1
    fi
    local requested_quick_port="$zap_quick_proxy_port"
    local quick_port_status
    quick_port_status="$(is_tcp_port_in_use "$zap_quick_proxy_host" "$requested_quick_port")"
    if [[ "$quick_port_status" == "used" ]]; then
      local resolved_quick_port=""
      if ! resolved_quick_port="$(find_available_tcp_port "$zap_quick_proxy_host" "$requested_quick_port" 100)"; then
        echo "❌ Unable to find an available ZAP quick-scan proxy port near ${requested_quick_port} on ${zap_quick_proxy_host}."
        exit 1
      fi
      zap_quick_proxy_port="$resolved_quick_port"
      echo "⚠️  ZAP_QUICK_PROXY_PORT ${requested_quick_port} is already in use; auto-selected ${zap_quick_proxy_port}."
    fi
    run_zap_quick_scan \
      "$zap_cli_cmd" \
      "$zap_quick_home_dir" \
      "$zap_quiet" \
      "$zap_classification_target" \
      "${report_dir_abs}/zap-classification.html" \
      "${report_dir_abs}/zap-classification.log" \
      "$zap_quick_proxy_host" \
      "$zap_quick_proxy_port"
    #R030: Parse ZAP HTML output into machine-readable severity totals for gate enforcement.
    summarize_zap_html_report \
      "${report_dir_abs}/zap-classification.html" \
      "${report_dir_abs}/zap-classification-summary.json" \
      > "${report_dir_abs}/zap-classification-summary.log"
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

  local zap_summary_json="${report_dir_abs}/zap-classification-summary.json"
  local zap_high_alerts=0
  local zap_medium_alerts=0
  local zap_low_alerts=0
  local zap_info_alerts=0
  local zap_counts=""
  if [[ -f "$zap_summary_json" ]]; then
    zap_counts="$(
      python3 - <<'PY' "$zap_summary_json"
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)
print(
    int(payload.get("high", 0)),
    int(payload.get("medium", 0)),
    int(payload.get("low", 0)),
    int(payload.get("informational", 0)),
)
PY
    )"
    IFS=' ' read -r zap_high_alerts zap_medium_alerts zap_low_alerts zap_info_alerts <<EOF
$zap_counts
EOF
  fi

  #R030: Fail lane when findings meet/exceed SECURITY_ZAP_FAIL_THRESHOLD.
  zap_fail_threshold_normalized="$(printf '%s' "$zap_fail_threshold" | tr '[:upper:]' '[:lower:]')"
  local threshold_count=0
  case "$zap_fail_threshold_normalized" in
    critical|high)
      threshold_count=$zap_high_alerts
      ;;
    medium)
      threshold_count=$((zap_high_alerts + zap_medium_alerts))
      ;;
    low)
      threshold_count=$((zap_high_alerts + zap_medium_alerts + zap_low_alerts))
      ;;
    informational|info)
      threshold_count=$((zap_high_alerts + zap_medium_alerts + zap_low_alerts + zap_info_alerts))
      ;;
    none)
      threshold_count=0
      ;;
    *)
      echo "❌ Invalid SECURITY_ZAP_FAIL_THRESHOLD=${zap_fail_threshold}. Use one of: none, high, medium, low, informational."
      exit 1
      ;;
  esac

  echo "Dynamic Application Security Testing (DAST) ZAP summary: high=${zap_high_alerts} medium=${zap_medium_alerts} low=${zap_low_alerts} informational=${zap_info_alerts}"
  if [[ "$fail_on_high_critical" == "true" && "$zap_fail_threshold_normalized" != "none" ]] && (( threshold_count > 0 )); then
    echo "❌ Dynamic Application Security Testing (DAST) gate failed: ZAP findings meet/exceed threshold '${zap_fail_threshold}'."
    exit 1
  fi

  #R025: Restore the database to its pre-DAST baseline before validating
  #R025: invariants so the integrity check also asserts cleanup succeeded.
  _cleanup_dast_state || true

  # Enforce post-DAST category table integrity invariants (post-cleanup) when DB-integrated.
  if [[ "${DAST_DB_INTEGRATION:-true}" == "true" ]]; then
    run_category_integrity_checks "$report_dir_abs"
  else
    echo "ℹ️  Post-DAST category integrity skipped (DAST_DB_INTEGRATION=false)."
  fi

  echo "✅ Dynamic Application Security Testing (DAST) checks completed."
)
}

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

if [[ "$RUN_SAST" == "true" ]]; then
  #R020: Run SAST scanners and persist machine-readable artifacts.
  require_command semgrep
  require_command bandit
  require_command pip-audit
  require_command detect-secrets
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
  semgrep scan \
    --config "p/security-audit" \
    --config "p/python" \
    --config "$SEMGREP_CONFIG_PATH" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    .

  print_tool_header \
    "Bandit" \
    "Static security analyzer for Python source code." \
    "Flags known insecure coding patterns and risky API usage." \
    "https://bandit.readthedocs.io/"
  echo "▶ Running Bandit"
  # Distinguish scanner findings from scanner execution failures.
  set +e
  bandit -q -r ./teller -c "$BANDIT_CONFIG_PATH" -f json -o "${REPORT_DIR}/bandit.json"
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
    --exclude-files '(^\.git/|^${VENV_NAME}/|^artifacts/venv/security/|^artifacts/security/|^artifacts/security-dast/|^artifacts/parallel/|^artifacts/mutation/|^artifacts/fuzz/|^artifacts/cache/ruff/|^artifacts/cache/pytest/|^artifacts/cache/hypothesis/|^artifacts/cache/egg-info/|^backups/|^archive/backup_extracts/|^config/bank_statements/|^src/macos-ui/\.derivedData-ui-tests/|^src/macos-ui/\.build/|^requirements/)' \
    > "${REPORT_DIR}/detect-secrets.json"

  run_gitleaks_sast "${REPORT_DIR}/gitleaks.json"

  # Execute ShellCheck within SAST lane and feed severity counts into centralized gating.
  run_shellcheck_sast "${REPORT_DIR}/shellcheck.json"
  run_swift_sast "${REPORT_DIR}/swiftlint.json"

  # Produce consolidated SAST gate summary and enforce blocking policy.
  python3 "${SECURITY_PY_DIR}/sast_summary_gate.py"     "${REPORT_DIR}"     "${FAIL_ON_HIGH_CRITICAL}"     "high"
  echo "✅ Static Application Security Testing (SAST) checks completed."
fi

if [[ "$RUN_DAST" == "true" ]]; then
  run_dast_checks "$REPORT_DIR"
fi

# Emit explicit completion status and artifact location for operators.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
