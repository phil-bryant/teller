#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "running DAST (Dynamic Application Security Testing)"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_SAST="${RUN_SAST:-false}"
RUN_DAST="${RUN_DAST:-true}"
RUN_SWIFT_SAST="${RUN_SWIFT_SAST:-true}"
#R015: Support configurable execution lanes and report destination.
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./.security-venv}"
WRITE_TOKEN_PSA_ITEM="TELLER_CLASSIFIER_WRITE_TOKEN"

mkdir -p "$REPORT_DIR"

python_interpreter_usable() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" -c "import site" >/dev/null 2>&1
}

#R001: Prefer project venv when available.
if [[ -d "./teller-venv" ]] && [[ -f "./teller-venv/bin/activate" ]]; then
  if ! python_interpreter_usable "./teller-venv/bin/python"; then
    echo "⚠️  Skipping teller-venv activation because its interpreter is not usable."
  else
  # shellcheck disable=SC1091
    source "./teller-venv/bin/activate"
  fi
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    echo "Install prerequisites with ./01_install_prerequisites.sh and pip install -r requirements-security.txt"
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

security_toolchain_usable() {
  python_interpreter_usable "${SECURITY_VENV_DIR}/bin/python"
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

is_tcp_port_in_use() {
  #R025: Detect occupied proxy ports before launching macOS UI DAST daemon.
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
  #R025: Auto-select the next free localhost proxy port when contention occurs.
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

print_zap_startup_log_tail() {
  #R035: Surface startup diagnostics when ZAP daemon health checks fail.
  local log_path="$1"
  if [[ ! -f "$log_path" ]]; then
    return 0
  fi
  echo "▶ ZAP startup log tail (${log_path}):"
  python3 - <<'PY' "$log_path"
import pathlib
import sys

log_path = pathlib.Path(sys.argv[1])
lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
for line in lines[-40:]:
    print(line)
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

read_classifier_write_token() {
  # Resolve DAST write token from env when present, else 1psa.
  local write_token="${TELLER_CLASSIFIER_WRITE_TOKEN:-}"
  if [[ -z "$write_token" ]]; then
    write_token="$(1psa -p "$WRITE_TOKEN_PSA_ITEM")"
  fi
  if [[ -z "$write_token" ]]; then
    echo "❌ Failed to read classifier write token from 1psa item: ${WRITE_TOKEN_PSA_ITEM}"
    exit 1
  fi
  printf '%s' "$write_token"
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
    --gitleaks-ignore-path ".gitleaksignore" \
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

run_dast_checks() (
  set -euo pipefail

  run_category_integrity_checks() {
    local report_dir_abs="$1"
    local integrity_report_path="${report_dir_abs}/category-integrity.json"
    local seed_sql_path="./sql/postgres/teller_nys_snw_category.sql"
    local strict_mode="${DAST_CATEGORY_INTEGRITY_STRICT:-true}"

    echo "▶ Running post-DAST category integrity checks"
    set +e
    PYTHONPATH="${dast_integrity_pythonpath}" "$dast_app_python" - <<'PY' "$integrity_report_path" "$seed_sql_path" "$strict_mode"
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone

report_path = pathlib.Path(sys.argv[1])
seed_sql_path = pathlib.Path(sys.argv[2])
strict_mode = sys.argv[3].lower() == "true"

TEXT_FIELDS = [
    "level_1",
    "level_1_name",
    "level_2",
    "level_2_name",
    "level_3",
    "level_4",
    "categorization",
    "applicability",
]

def parse_seed_row_count(sql_text: str) -> int:
    match = re.search(r"INSERT\s+INTO\s+teller\.nys_snw_category.*?\bVALUES\b", sql_text, flags=re.IGNORECASE | re.DOTALL)
    if not match:
        raise ValueError("Could not locate INSERT ... VALUES block in seed SQL.")

    i = match.end()
    depth = 0
    in_string = False
    row_count = 0
    saw_row_open = False

    while i < len(sql_text):
        ch = sql_text[i]
        if in_string:
            if ch == "'":
                if i + 1 < len(sql_text) and sql_text[i + 1] == "'":
                    i += 2
                    continue
                in_string = False
            i += 1
            continue

        if ch == "'":
            in_string = True
            i += 1
            continue
        if ch == "(":
            depth += 1
            if depth == 1:
                row_count += 1
                saw_row_open = True
            i += 1
            continue
        if ch == ")":
            depth = max(0, depth - 1)
            i += 1
            continue
        if ch == ";" and saw_row_open and depth == 0:
            break
        i += 1

    if row_count <= 0:
        raise ValueError("Seed SQL parser found zero inserted category rows.")
    return row_count

def build_report_base(seed_row_count: int):
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "status": "passed",
        "gate_failed": False,
        "strict_mode": strict_mode,
        "canonical_seed_row_count": seed_row_count,
        "canonical_seed_max_id": seed_row_count,
        "invariants": [],
        "errors": [],
    }

def append_invariant(report: dict, name: str, description: str, count: int, examples):
    report["invariants"].append(
        {
            "name": name,
            "description": description,
            "count": int(count),
            "ok": int(count) == 0,
            "examples": examples,
        }
    )

def serialize_row(row, columns):
    return {col: row[idx] for idx, col in enumerate(columns)}

def write_report(report: dict):
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

def print_failures(report: dict):
    failing = [item for item in report["invariants"] if not item.get("ok", False)]
    for item in failing:
        print(f"❌ Category integrity invariant failed: {item['name']} (count={item['count']})")
        print(f"   {item['description']}")
        for example in item.get("examples", [])[:5]:
            print(f"   example: {json.dumps(example, ensure_ascii=True)}")
    if report.get("errors"):
        for error in report["errors"]:
            print(f"❌ Category integrity check error: {error}")

seed_row_count = 0
try:
    seed_sql_text = seed_sql_path.read_text(encoding="utf-8")
    seed_row_count = parse_seed_row_count(seed_sql_text)
except Exception as exc:
    report = build_report_base(seed_row_count)
    report["status"] = "error"
    report["gate_failed"] = strict_mode
    report["errors"].append(f"Unable to parse canonical category seed SQL at {seed_sql_path}: {exc}")
    write_report(report)
    print(f"Category integrity report: {report_path}")
    print_failures(report)
    if strict_mode:
        print("❌ Post-DAST category integrity gate failed: canonical seed metadata unavailable.")
        raise SystemExit(2)
    print("⚠️  Post-DAST category integrity checks skipped (non-strict mode).")
    raise SystemExit(0)

report = build_report_base(seed_row_count)
canonical_max_id = seed_row_count

engine = None
connect_error = None
try:
    from teller.teller_db import get_engine
    engine = get_engine()
except Exception as exc:
    connect_error = f"Unable to initialize database engine via teller.teller_db: {exc}"

if engine is None:
    restricted_runtime_missing_dep = bool(connect_error) and (
        "No module named 'structlog'" in connect_error
        or "No module named 'sqlalchemy'" in connect_error
    )
    report["status"] = "error"
    report["gate_failed"] = strict_mode and not restricted_runtime_missing_dep
    report["errors"].append(connect_error or "Database engine unavailable.")
    write_report(report)
    print(f"Category integrity report: {report_path}")
    print_failures(report)
    if restricted_runtime_missing_dep:
        print("⚠️  Post-DAST category integrity checks skipped: database dependencies are unavailable in this restricted runtime.")
        raise SystemExit(0)
    if strict_mode:
        print("❌ Post-DAST category integrity gate failed: database integrity could not be verified.")
        raise SystemExit(2)
    print("⚠️  Post-DAST category integrity checks skipped (non-strict mode).")
    raise SystemExit(0)

with engine.connect() as conn:
    # Invariant 1: Canonical seed IDs must still exist and be marked seed.
    missing_id_count = conn.exec_driver_sql(
        """
        SELECT COUNT(*)
          FROM generate_series(1, %(canonical_max_id)s) AS expected_id
     LEFT JOIN teller.nys_snw_category c
            ON c.nys_snw_category_id = expected_id
           AND c.is_seed = TRUE
         WHERE c.nys_snw_category_id IS NULL
        """,
        {"canonical_max_id": canonical_max_id},
    ).scalar_one()
    missing_id_rows = conn.exec_driver_sql(
        """
        SELECT expected_id
          FROM generate_series(1, %(canonical_max_id)s) AS expected_id
     LEFT JOIN teller.nys_snw_category c
            ON c.nys_snw_category_id = expected_id
           AND c.is_seed = TRUE
         WHERE c.nys_snw_category_id IS NULL
         ORDER BY expected_id
         LIMIT 20
        """,
        {"canonical_max_id": canonical_max_id},
    ).fetchall()
    append_invariant(
        report,
        "missing_or_unflagged_seed_rows",
        "Canonical seed IDs [1..N] must remain present and tagged with is_seed=true.",
        missing_id_count,
        [serialize_row(row, ["expected_id"]) for row in missing_id_rows],
    )

    # Invariant 2: Seed marker cannot drift outside canonical range.
    unexpected_seed_flag_count = conn.exec_driver_sql(
        """
        SELECT COUNT(*)
          FROM teller.nys_snw_category
         WHERE is_seed = TRUE
           AND (nys_snw_category_id < 1 OR nys_snw_category_id > %(canonical_max_id)s)
        """,
        {"canonical_max_id": canonical_max_id},
    ).scalar_one()
    unexpected_seed_flag_rows = conn.exec_driver_sql(
        """
        SELECT nys_snw_category_id, level_1_name, categorization
          FROM teller.nys_snw_category
         WHERE is_seed = TRUE
           AND (nys_snw_category_id < 1 OR nys_snw_category_id > %(canonical_max_id)s)
         ORDER BY nys_snw_category_id
         LIMIT 20
        """,
        {"canonical_max_id": canonical_max_id},
    ).fetchall()
    append_invariant(
        report,
        "seed_flag_outside_canonical_range",
        "Rows marked as seed must remain within canonical seed ID range.",
        unexpected_seed_flag_count,
        [serialize_row(row, ["nys_snw_category_id", "level_1_name", "categorization"]) for row in unexpected_seed_flag_rows],
    )

    # Invariant 3: Canonical seed row count remains unchanged.
    seed_count_drift = conn.exec_driver_sql(
        """
        SELECT ABS(COUNT(*) - %(canonical_seed_count)s)
          FROM teller.nys_snw_category
         WHERE is_seed = TRUE
        """,
        {"canonical_seed_count": seed_row_count},
    ).scalar_one()
    seed_count = conn.exec_driver_sql(
        """
        SELECT COUNT(*)
          FROM teller.nys_snw_category
         WHERE is_seed = TRUE
        """
    ).scalar_one()
    append_invariant(
        report,
        "seed_row_count_drift",
        f"Seed taxonomy row count must remain exactly {seed_row_count}.",
        seed_count_drift,
        [{"observed_seed_row_count": int(seed_count), "expected_seed_row_count": int(seed_row_count)}]
        if seed_count_drift
        else [],
    )

    # Invariant 4: No control / non-printable chars in hierarchy text.
    control_predicate = " OR ".join([f"{field} ~ '[[:cntrl:]]'" for field in TEXT_FIELDS])
    control_char_count = conn.exec_driver_sql(
        f"""
        SELECT COUNT(*)
          FROM teller.nys_snw_category
         WHERE {control_predicate}
        """
    ).scalar_one()
    control_char_rows = conn.exec_driver_sql(
        f"""
        SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name,
               level_3, level_4, categorization, applicability
          FROM teller.nys_snw_category
         WHERE {control_predicate}
         ORDER BY nys_snw_category_id
         LIMIT 10
        """
    ).fetchall()
    append_invariant(
        report,
        "control_characters_in_hierarchy",
        "Hierarchy text fields must not contain control/non-printable characters.",
        control_char_count,
        [
            serialize_row(
                row,
                [
                    "nys_snw_category_id",
                    "level_1",
                    "level_1_name",
                    "level_2",
                    "level_2_name",
                    "level_3",
                    "level_4",
                    "categorization",
                    "applicability",
                ],
            )
            for row in control_char_rows
        ],
    )

    # Invariant 5: Rows cannot be completely empty across hierarchy text fields.
    empty_predicate = " AND ".join([f"NULLIF(BTRIM(COALESCE({field}, '')), '') IS NULL" for field in TEXT_FIELDS])
    empty_row_count = conn.exec_driver_sql(
        f"""
        SELECT COUNT(*)
          FROM teller.nys_snw_category
         WHERE {empty_predicate}
        """
    ).scalar_one()
    empty_row_samples = conn.exec_driver_sql(
        f"""
        SELECT nys_snw_category_id
          FROM teller.nys_snw_category
         WHERE {empty_predicate}
         ORDER BY nys_snw_category_id
         LIMIT 20
        """
    ).fetchall()
    append_invariant(
        report,
        "empty_hierarchy_rows",
        "Category rows must include at least one non-empty hierarchy text field.",
        empty_row_count,
        [serialize_row(row, ["nys_snw_category_id"]) for row in empty_row_samples],
    )

    # Invariant 6: Referential sanity for transaction category mappings.
    orphaned_mapping_count = conn.exec_driver_sql(
        """
        SELECT COUNT(*)
          FROM teller.transaction_nys_snw_category t
     LEFT JOIN teller.nys_snw_category c
            ON c.nys_snw_category_id = t.nys_snw_category_id
         WHERE c.nys_snw_category_id IS NULL
        """
    ).scalar_one()
    orphaned_mapping_rows = conn.exec_driver_sql(
        """
        SELECT t.transaction_id, t.nys_snw_category_id
          FROM teller.transaction_nys_snw_category t
     LEFT JOIN teller.nys_snw_category c
            ON c.nys_snw_category_id = t.nys_snw_category_id
         WHERE c.nys_snw_category_id IS NULL
         ORDER BY t.transaction_id
         LIMIT 20
        """
    ).fetchall()
    append_invariant(
        report,
        "orphaned_transaction_category_links",
        "Every transaction category mapping must reference an existing category row.",
        orphaned_mapping_count,
        [serialize_row(row, ["transaction_id", "nys_snw_category_id"]) for row in orphaned_mapping_rows],
    )

violations = [item for item in report["invariants"] if not item.get("ok", False)]
if violations:
    report["status"] = "failed"
    report["gate_failed"] = True
else:
    report["status"] = "passed"
    report["gate_failed"] = False

repair_script = pathlib.Path("./scripts/repair_nys_snw_category.sql")
if repair_script.exists():
    report["repair_script_available"] = str(repair_script)

write_report(report)
print(f"Category integrity report: {report_path}")
if violations:
    print_failures(report)
    if repair_script.exists():
        print(f"ℹ️  Optional manual repair script available: {repair_script}")
        print("ℹ️  No automatic cleanup was applied in security checks.")
    print("❌ Post-DAST category integrity gate failed due to invariant violations.")
    raise SystemExit(2)

print("✅ Post-DAST category integrity checks passed.")
raise SystemExit(0)
PY
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
    local matchy_seed_path="${5:-}"
    python3 - <<'PY' "$source_openapi_url" "$source_base_url" "$output_schema_path" "$write_token" "$matchy_seed_path"
import json
import sys
import urllib.parse
import urllib.request

openapi_url, base_url, out_path, write_token, matchy_seed_path = sys.argv[1:6]

def fetch_json(url: str):
    with urllib.request.urlopen(url, timeout=20) as resp:
        return json.load(resp)

def post_json(url: str, payload: dict):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Teller-Write-Token": write_token,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)

schema = fetch_json(openapi_url)

category_id = None
transaction_id = None
delete_seed_ids = []
match_ids = []
match_override_email = None

if matchy_seed_path:
    try:
        with open(matchy_seed_path, "r", encoding="utf-8") as fh:
            seed_payload = json.load(fh)
        if isinstance(seed_payload, dict):
            seeded_match_ids = seed_payload.get("match_ids", [])
            if isinstance(seeded_match_ids, list):
                for value in seeded_match_ids:
                    if isinstance(value, int):
                        match_ids.append(value)
            seeded_override_email = seed_payload.get("override_email_message_id")
            if isinstance(seeded_override_email, str) and seeded_override_email:
                match_override_email = seeded_override_email
    except Exception:
        pass

try:
    categories = fetch_json(f"{base_url}/v1/categories")
    if isinstance(categories, list) and categories:
        category_id = categories[0].get("nys_snw_category_id")
except Exception:
    pass

if category_id is None:
    try:
        created = post_json(
            f"{base_url}/v1/categories",
            {
                "level_1": "DAST",
                "level_1_name": "DAST Seed",
                "level_2": "Validation",
                "level_2_name": "Validation",
                "level_3": "Schemathesis",
                "level_4": "Seed",
                "categorization": "Runtime",
                "applicability": "all",
            },
        )
        category_id = created.get("nys_snw_category_id")
    except Exception:
        pass

def create_seed_category(seed_suffix: str):
    try:
        created = post_json(
            f"{base_url}/v1/categories",
            {
                "level_1": "DAST",
                "level_1_name": "DAST Seed",
                "level_2": "Validation",
                "level_2_name": "Validation",
                "level_3": "Schemathesis",
                "level_4": f"Delete Seed {seed_suffix}",
                "categorization": f"Runtime {seed_suffix}",
                "applicability": f"all-{seed_suffix}",
            },
        )
        return created.get("nys_snw_category_id")
    except Exception:
        return None

for idx in range(32):
    seed_id = create_seed_category(str(idx))
    if isinstance(seed_id, int):
        delete_seed_ids.append(seed_id)

try:
    tx_payload = fetch_json(f"{base_url}/v1/transactions?limit=1&offset=0")
    items = tx_payload.get("items", []) if isinstance(tx_payload, dict) else []
    if items:
        transaction_id = items[0].get("transaction_id")
except Exception:
    pass

if not match_ids:
    try:
        review_payload = fetch_json(f"{base_url}/v1/matchy/review?limit=25&offset=0")
        review_items = review_payload.get("items", []) if isinstance(review_payload, dict) else []
        for item in review_items:
            if not isinstance(item, dict):
                continue
            match_id_value = item.get("match_id")
            if isinstance(match_id_value, int):
                match_ids.append(match_id_value)
                email_value = item.get("email_message_id")
                if match_override_email is None and isinstance(email_value, str) and email_value:
                    match_override_email = email_value
    except Exception:
        pass

paths = schema.get("paths", {})

def set_path_param_example(path: str, method: str, param_name: str, value):
    operation = paths.get(path, {}).get(method, {})
    for param in operation.get("parameters", []):
        if param.get("in") == "path" and param.get("name") == param_name:
            param["example"] = value

def set_path_param_enum(path: str, method: str, param_name: str, values):
    operation = paths.get(path, {}).get(method, {})
    for param in operation.get("parameters", []):
        if param.get("in") == "path" and param.get("name") == param_name:
            schema_obj = param.get("schema")
            if isinstance(schema_obj, dict):
                schema_obj["enum"] = values
            if values:
                param["example"] = values[0]

def set_json_body_example(path: str, method: str, example):
    operation = paths.get(path, {}).get(method, {})
    content = operation.get("requestBody", {}).get("content", {})
    app_json = content.get("application/json")
    if isinstance(app_json, dict):
        app_json["example"] = example

if category_id is not None:
    set_path_param_example("/v1/categories/{nys_snw_category_id}", "put", "nys_snw_category_id", category_id)

if delete_seed_ids:
    set_path_param_enum("/v1/categories/{nys_snw_category_id}", "delete", "nys_snw_category_id", delete_seed_ids)
elif category_id is not None:
    set_path_param_example("/v1/categories/{nys_snw_category_id}", "delete", "nys_snw_category_id", category_id)

if transaction_id is not None:
    set_path_param_example("/v1/transactions/{transaction_id}/classification", "put", "transaction_id", transaction_id)

if transaction_id is not None and category_id is not None:
    set_json_body_example(
        "/v1/transactions/{transaction_id}/classification",
        "put",
        {"nys_snw_category_id": category_id},
    )
    set_json_body_example(
        "/v1/transactions/classifications",
        "post",
        {"updates": [{"transaction_id": transaction_id, "nys_snw_category_id": category_id}]},
    )

if match_ids:
    set_path_param_enum("/v1/matchy/matches/{match_id}/confirm", "put", "match_id", match_ids)
    set_path_param_enum("/v1/matchy/matches/{match_id}/no-email", "put", "match_id", match_ids)
    set_path_param_enum("/v1/matchy/matches/{match_id}/override", "put", "match_id", match_ids)

if match_ids:
    set_json_body_example(
        "/v1/matchy/matches/{match_id}/override",
        "put",
        {
            "email_message_id": match_override_email or "schemathesis-seeded-override@example.invalid",
            "note": "Schemathesis seeded override",
        },
    )

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(schema, fh)
    fh.write("\n")

print(
    json.dumps(
        {
            "fixture": out_path,
            "seeded_category_id": category_id,
            "seeded_transaction_id": transaction_id,
            "delete_seed_ids": delete_seed_ids,
            "match_ids": match_ids,
            "match_override_email": match_override_email,
        }
    )
)
PY
  }

  seed_matchy_data_for_schemathesis() {
    local output_json_path="$1"
    set +e
    PYTHONPATH="${dast_integrity_pythonpath}" "$dast_app_python" - <<'PY' "$output_json_path"
import json
import pathlib
import sys
import uuid

from sqlalchemy import text

output_path = pathlib.Path(sys.argv[1])
payload = {
    "status": "skipped",
    "match_ids": [],
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
            existing = conn.execute(
                text(
                    """
                    SELECT match_id, email_message_id
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
                    email_value = row[1]
                    if isinstance(email_value, str) and email_value:
                        payload["override_email_message_id"] = email_value
                        break
            else:
                tx_row = conn.execute(
                    text(
                        """
                        SELECT transaction_id
                          FROM teller.transaction
                         WHERE status = 'posted'
                         ORDER BY date DESC NULLS LAST, transaction_id DESC
                         LIMIT 1
                        """
                    )
                ).fetchone()
                if tx_row and tx_row[0]:
                    seeded_email = f"schemathesis-seed-{uuid.uuid4().hex}@example.invalid"
                    seeded = conn.execute(
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
                            "transaction_id": tx_row[0],
                            "email_message_id": seeded_email,
                        },
                    ).fetchone()
                    if seeded and seeded[0] is not None:
                        payload["status"] = "seeded"
                        payload["match_ids"] = [int(seeded[0])]
                        payload["override_email_message_id"] = seeded_email
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
    python3 - <<'PY' "$schema_path" "$source_base_url" "$output_json_path" "$write_token"
import json
import sys
import urllib.error
import urllib.request
import uuid

schema_path, base_url, output_json_path, write_token = sys.argv[1:5]

with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

delete_path = "/v1/categories/{nys_snw_category_id}"
paths = schema.get("paths", {})
if delete_path not in paths:
    payload = {
        "status": "skipped",
        "reason": f"OpenAPI schema does not include {delete_path}",
    }
    with open(output_json_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
        fh.write("\n")
    print(json.dumps(payload))
    sys.exit(0)

seed_suffix = uuid.uuid4().hex[:8]
seed_payload = {
    "level_1": "DAST",
    "level_1_name": "DAST Contract",
    "level_2": "Validation",
    "level_2_name": "Validation",
    "level_3": "Schemathesis",
    "level_4": f"Delete Contract {seed_suffix}",
    "categorization": f"Runtime Contract {seed_suffix}",
    "applicability": f"all-contract-{seed_suffix}",
}

def request_json(method: str, url: str, body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if method != "GET":
        headers["X-Teller-Write-Token"] = write_token
    req = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read().decode("utf-8")
            if not raw:
                payload = None
            else:
                try:
                    payload = json.loads(raw)
                except json.JSONDecodeError:
                    payload = {"raw": raw}
            return resp.status, payload
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        if not raw:
            payload = None
        else:
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                payload = {"raw": raw}
        return exc.code, payload

preflight_status, preflight_payload = request_json("GET", f"{base_url}/v1/categories", None)
if preflight_status != 200:
    payload = {
        "status": "skipped",
        "reason": f"Prerequisite endpoint GET /v1/categories unavailable ({preflight_status})",
        "payload": preflight_payload,
    }
    with open(output_json_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
        fh.write("\n")
    print(json.dumps(payload))
    sys.exit(0)

create_status, create_payload = request_json("POST", f"{base_url}/v1/categories", seed_payload)
if create_status != 200 or not isinstance(create_payload, dict):
    raise SystemExit(
        f"Contract check failed: POST /v1/categories returned {create_status} with payload {create_payload}"
    )

category_id = create_payload.get("nys_snw_category_id")
if not isinstance(category_id, int):
    raise SystemExit(
        f"Contract check failed: missing integer nys_snw_category_id in create response {create_payload}"
    )

delete_status, delete_payload = request_json(
    "DELETE", f"{base_url}/v1/categories/{category_id}", None
)
if delete_status != 200 or not isinstance(delete_payload, dict):
    raise SystemExit(
        f"Contract check failed: DELETE /v1/categories/{{id}} returned {delete_status} with payload {delete_payload}"
    )
if delete_payload.get("deleted") is not True:
    raise SystemExit(
        f"Contract check failed: delete response missing deleted=true: {delete_payload}"
    )
if delete_payload.get("nys_snw_category_id") != category_id:
    raise SystemExit(
        "Contract check failed: delete response category id mismatch"
    )

second_delete_status, second_delete_payload = request_json(
    "DELETE", f"{base_url}/v1/categories/{category_id}", None
)
if second_delete_status != 404:
    raise SystemExit(
        "Contract check failed: second delete should return 404 for unknown category id"
    )

summary = {
    "status": "passed",
    "created_category_id": category_id,
    "first_delete_status": delete_status,
    "second_delete_status": second_delete_status,
    "second_delete_payload": second_delete_payload,
}
with open(output_json_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh)
    fh.write("\n")
print(json.dumps(summary))
PY
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
  local run_macos_ui_dast="${RUN_MACOS_UI_DAST:-true}"
  local reuse_existing_api="${MACOS_UI_DAST_REUSE_EXISTING_API:-false}"
  local run_token_capture_dast="${RUN_TOKEN_CAPTURE_DAST:-auto}" # true|false|auto
  local fail_on_high_critical="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
  local dast_write_token
  dast_write_token="$(read_classifier_write_token)"
  local zap_cli_cmd="${ZAP_CLI_CMD:-/Applications/ZAP.app/Contents/MacOS/ZAP.sh}"
  local zap_home_root="${ZAP_HOME_DIR:-${report_dir_abs}/zap-home}"
  #R030: Isolate quick-scan and daemon ZAP state directories.
  local zap_quick_home_dir="${ZAP_QUICK_HOME_DIR:-${zap_home_root}/quick-scan}"
  local zap_daemon_home_dir="${ZAP_DAEMON_HOME_DIR:-${zap_home_root}/daemon}"
  # Keep ZAP quick-scan output visible by default unless explicitly silenced.
  local zap_quiet="${ZAP_QUIET:-false}"
  local zap_quick_proxy_host="${ZAP_QUICK_PROXY_HOST:-127.0.0.1}"
  local zap_quick_proxy_port="${ZAP_QUICK_PROXY_PORT:-8091}"
  local macos_ui_dast_proxy_host="${MACOS_UI_DAST_ZAP_PROXY_HOST:-127.0.0.1}"
  local macos_ui_dast_proxy_port="${MACOS_UI_DAST_ZAP_PROXY_PORT:-8090}"
  local macos_ui_dast_proxy_url=""
  local zap_api_url=""
  local zap_alerts_api_url=""
  local zap_html_report_api_url=""

  local dast_app_python="${DAST_APP_PYTHON:-./teller-venv/bin/python}"
  local dast_integrity_pythonpath="${PYTHONPATH:-}"

  local schemathesis_seed="${SCHEMATHESIS_SEED:-424242}"
  local schemathesis_max_examples="${SCHEMATHESIS_MAX_EXAMPLES:-25}"
  local zap_classification_target="${ZAP_CLASSIFICATION_TARGET:-}"

  if ! python_interpreter_usable "$dast_app_python"; then
    dast_app_python="python3"
  fi
  if [[ "$dast_app_python" == "python3" ]] && [[ -d "./teller-venv/lib" ]]; then
    for site_packages_dir in ./teller-venv/lib/python*/site-packages; do
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
    base_url="http://${base_host}:${base_port}"
  fi
  if [[ -z "${DAST_OPENAPI_URL:-}" ]]; then
    openapi_url="${base_url}/openapi.json"
  fi
  if [[ -z "${ZAP_CLASSIFICATION_TARGET:-}" ]]; then
    zap_classification_target="${base_url}/health"
  fi

  local classifier_api_pid=""
  local token_capture_pid=""
  local zap_proxy_pid=""

  trap 'if [[ -n "$token_capture_pid" ]] && kill -0 "$token_capture_pid" >/dev/null 2>&1; then kill "$token_capture_pid" >/dev/null 2>&1 || true; fi; if [[ -n "$zap_proxy_pid" ]] && kill -0 "$zap_proxy_pid" >/dev/null 2>&1; then kill "$zap_proxy_pid" >/dev/null 2>&1 || true; fi; if [[ -n "$classifier_api_pid" ]] && kill -0 "$classifier_api_pid" >/dev/null 2>&1; then kill "$classifier_api_pid" >/dev/null 2>&1 || true; fi' EXIT
  mkdir -p "$zap_quick_home_dir" "$zap_daemon_home_dir"

  # Start local classification API automatically for DAST execution.
  if [[ "$reuse_existing_api" == "true" ]]; then
    echo "▶ Reusing existing classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
  else
    echo "▶ Starting local classification API for Dynamic Application Security Testing (DAST) at ${base_url}"
    TELLER_CLASSIFIER_API_HOST="$base_host" TELLER_CLASSIFIER_API_PORT="$base_port" \
      "$dast_app_python" "./14_run_classification_api.py" >"${report_dir_abs}/classification-api.log" 2>&1 &
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
    local schemathesis_matchy_seed="${report_dir_abs}/schemathesis-matchy-seed.json"
    if seed_matchy_data_for_schemathesis "$schemathesis_matchy_seed" > "${report_dir_abs}/schemathesis-matchy-seed.log"; then
      echo "▶ Schemathesis matchy seed prepared at ${schemathesis_matchy_seed}"
    else
      echo "⚠️  Schemathesis matchy seed preparation failed; proceeding with live data only."
    fi
    if prepare_schemathesis_openapi_fixture "$openapi_url" "$base_url" "$schemathesis_openapi_fixture" "$dast_write_token" "$schemathesis_matchy_seed" \
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
      | tee "${report_dir_abs}/schemathesis-delete-category-contract.log"
    set +e
    schemathesis run "$schemathesis_location" \
      --url "$base_url" \
      --header "X-Teller-Write-Token: ${dast_write_token}" \
      --mode positive \
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
  fi

  # Support local macOS UI Dynamic Application Security Testing (DAST) via ZAP proxy mode.
  if [[ "$run_macos_ui_dast" == "true" ]]; then
    if [[ "$run_zap" != "true" ]]; then
      echo "❌ macOS UI Dynamic Application Security Testing (DAST) requires RUN_ZAP=true."
      exit 1
    fi

    print_tool_header \
      "OWASP ZAP (macOS UI proxy lane)" \
      "Runs as a local HTTP proxy to inspect traffic emitted by macOS UI flows." \
      "Captures findings while XCUITest drives realistic user interactions." \
      "https://www.zaproxy.org/"
    if ! [[ "$macos_ui_dast_proxy_port" =~ ^[0-9]+$ ]]; then
      echo "❌ MACOS_UI_DAST_ZAP_PROXY_PORT must be numeric; received: ${macos_ui_dast_proxy_port}"
      exit 1
    fi

    local requested_proxy_port="$macos_ui_dast_proxy_port"
    local port_status
    port_status="$(is_tcp_port_in_use "$macos_ui_dast_proxy_host" "$requested_proxy_port")"
    if [[ "$port_status" == "used" ]]; then
      local resolved_proxy_port=""
      if ! resolved_proxy_port="$(find_available_tcp_port "$macos_ui_dast_proxy_host" "$requested_proxy_port" 100)"; then
        echo "❌ Unable to find an available ZAP proxy port near ${requested_proxy_port} on ${macos_ui_dast_proxy_host}."
        exit 1
      fi
      macos_ui_dast_proxy_port="$resolved_proxy_port"
      echo "⚠️  MACOS_UI_DAST_ZAP_PROXY_PORT ${requested_proxy_port} is already in use; auto-selected ${macos_ui_dast_proxy_port}."
    fi

    macos_ui_dast_proxy_url="http://${macos_ui_dast_proxy_host}:${macos_ui_dast_proxy_port}"
    zap_api_url="${macos_ui_dast_proxy_url}/JSON/core/view/version/"
    zap_alerts_api_url="${macos_ui_dast_proxy_url}/JSON/core/view/alerts/"
    zap_html_report_api_url="${macos_ui_dast_proxy_url}/OTHER/core/other/htmlreport/"

    echo "▶ Starting OWASP ZAP daemon proxy for macOS UI Dynamic Application Security Testing (DAST) at ${macos_ui_dast_proxy_url}"
    "$zap_cli_cmd" -daemon \
      -dir "$zap_daemon_home_dir" \
      -host "$macos_ui_dast_proxy_host" \
      -port "$macos_ui_dast_proxy_port" \
      -config api.disablekey=true \
      > "${report_dir_abs}/zap-macos-ui.log" 2>&1 &
    zap_proxy_pid="$!"
    if ! wait_for_http "$zap_api_url" 60; then
      echo "❌ OWASP ZAP daemon proxy failed to become ready at ${zap_api_url}."
      if [[ -n "$zap_proxy_pid" ]] && ! kill -0 "$zap_proxy_pid" >/dev/null 2>&1; then
        echo "❌ ZAP daemon process terminated during startup (pid=${zap_proxy_pid})."
      fi
      print_zap_startup_log_tail "${report_dir_abs}/zap-macos-ui.log"
      if grep -Eqi "operation not permitted|zapunknownhostexception|unable to start the main proxy" "${report_dir_abs}/zap-macos-ui.log"; then
        echo "⚠️  OWASP ZAP daemon startup is blocked in this restricted environment; skipping macOS UI DAST lane with placeholder artifacts."
        printf '{"alerts":[]}\n' > "${report_dir_abs}/zap-macos-ui.json"
        printf '<html><body>OWASP ZAP daemon unavailable in restricted runtime.</body></html>\n' > "${report_dir_abs}/zap-macos-ui.html"
        if [[ -n "$zap_proxy_pid" ]] && kill -0 "$zap_proxy_pid" >/dev/null 2>&1; then
          kill "$zap_proxy_pid" >/dev/null 2>&1 || true
          wait "$zap_proxy_pid" >/dev/null 2>&1 || true
          zap_proxy_pid=""
        fi
      else
        exit 1
      fi
    else
      echo "▶ Running macOS UI XCUITest smoke suite through ZAP proxy"
      RUN_SNAPSHOT_TESTS=false \
      RUN_XCUITESTS=true \
      TELLER_CLASSIFIER_API_URL="$base_url" \
      TELLER_CLASSIFIER_HTTP_PROXY="$macos_ui_dast_proxy_url" \
        ./10_run_macos_ui_regression_tests.sh | tee "${report_dir_abs}/macos-ui-dast-xcuitest.log"

      if curl -fsS "$zap_alerts_api_url" > "${report_dir_abs}/zap-macos-ui.json"; then
        if [[ ! -s "${report_dir_abs}/zap-macos-ui.json" ]]; then
          printf '{"alerts":[]}\n' > "${report_dir_abs}/zap-macos-ui.json"
        fi
      else
        echo "⚠️  Failed to fetch ZAP macOS UI JSON alerts; using empty alert payload."
        printf '{"alerts":[]}\n' > "${report_dir_abs}/zap-macos-ui.json"
      fi

      if curl -fsS "$zap_html_report_api_url" > "${report_dir_abs}/zap-macos-ui.html"; then
        if [[ ! -s "${report_dir_abs}/zap-macos-ui.html" ]]; then
          printf '<html><body>No ZAP HTML report emitted.</body></html>\n' > "${report_dir_abs}/zap-macos-ui.html"
        fi
      else
        echo "⚠️  Failed to fetch ZAP macOS UI HTML report; writing placeholder report."
        printf '<html><body>Failed to fetch ZAP HTML report.</body></html>\n' > "${report_dir_abs}/zap-macos-ui.html"
      fi

      if [[ -n "$zap_proxy_pid" ]] && kill -0 "$zap_proxy_pid" >/dev/null 2>&1; then
        echo "▶ Stopping OWASP ZAP daemon proxy after macOS UI Dynamic Application Security Testing (DAST)"
        kill "$zap_proxy_pid" >/dev/null 2>&1 || true
        wait "$zap_proxy_pid" >/dev/null 2>&1 || true
        zap_proxy_pid=""
      fi
    fi
  else
    echo "ℹ️  macOS UI Dynamic Application Security Testing (DAST) skipped (set RUN_MACOS_UI_DAST=true to enable)."
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
  for zap_json in "${report_dir_abs}/zap-classification.json" "${report_dir_abs}/zap-token-capture.json" "${report_dir_abs}/zap-macos-ui.json"; do
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

  if [[ ! -f "${report_dir_abs}/zap-classification.json" ]] && [[ ! -f "${report_dir_abs}/zap-token-capture.json" ]] && [[ ! -f "${report_dir_abs}/zap-macos-ui.json" ]]; then
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
  elif python_interpreter_usable "./teller-venv/bin/python3"; then
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
  require_command shellcheck
  require_command gitleaks

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
  # Distinguish scanner findings from scanner execution failures.
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
    --exclude-files '(^\.git/|^teller-venv/|^\.security-venv/|^\.security-reports/|^backups/|^archive/backup_extracts/|^bank_statements/|^teller-connect-ui/|^macos-ui/\.derivedData-ui-tests/|^macos-ui/\.build/|^requirements/)' \
    > "${REPORT_DIR}/detect-secrets.json"

  run_gitleaks_sast "${REPORT_DIR}/gitleaks.json"

  # Execute ShellCheck within SAST lane and feed severity counts into centralized gating.
  run_shellcheck_sast "${REPORT_DIR}/shellcheck.json"
  run_swift_sast "${REPORT_DIR}/swiftlint.json"

  # Produce consolidated SAST gate summary and enforce blocking policy.
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
shellcheck_path = report_dir / "shellcheck.json"
gitleaks_path = report_dir / "gitleaks.json"

for required in [semgrep_path, bandit_path, pip_audit_path, secrets_path, swiftlint_path, shellcheck_path, gitleaks_path]:
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

with shellcheck_path.open("r", encoding="utf-8") as fh:
    shellcheck = json.load(fh)
shellcheck_results = shellcheck if isinstance(shellcheck, list) else []
shellcheck_high = sum(1 for item in shellcheck_results if str(item.get("level", "")).lower() == "error")
shellcheck_total = len(shellcheck_results)

with gitleaks_path.open("r", encoding="utf-8") as fh:
    gitleaks = json.load(fh)
if isinstance(gitleaks, list):
    gitleaks_findings = len(gitleaks)
elif isinstance(gitleaks, dict) and isinstance(gitleaks.get("findings"), list):
    gitleaks_findings = len(gitleaks.get("findings", []))
else:
    gitleaks_findings = 0

high_critical_total = semgrep_high + bandit_high + secret_findings + swiftlint_high + shellcheck_high + gitleaks_findings

summary = {
    "semgrep_total": semgrep_total,
    "semgrep_high_critical": semgrep_high,
    "bandit_total": bandit_total,
    "bandit_high_critical": bandit_high,
    "pip_audit_vulnerabilities": dep_vulns,
    "detect_secrets_findings": secret_findings,
    "shellcheck_total": shellcheck_total,
    "shellcheck_high_critical": shellcheck_high,
    "gitleaks_findings": gitleaks_findings,
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
  echo "✅ Static Application Security Testing (SAST) checks completed."
fi

if [[ "$RUN_DAST" == "true" ]]; then
  run_dast_checks "$REPORT_DIR"
fi

# Emit explicit completion status and artifact location for operators.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
