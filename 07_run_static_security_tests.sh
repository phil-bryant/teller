#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "running SAST (Static Application Security Testing)"

REPORT_DIR="${SECURITY_REPORT_DIR:-./artifacts/security/reports}"
RUN_SAST="${RUN_SAST:-true}"
RUN_DAST="${RUN_DAST:-false}"
RUN_SWIFT_SAST="${RUN_SWIFT_SAST:-true}"
#R015: Support configurable execution lanes and report destination.
#R090: Default financial-app policy blocks medium-or-higher security findings.
FAIL_ON_MEDIUM_OR_HIGHER="${SECURITY_FAIL_ON_MEDIUM_OR_HIGHER:-${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./artifacts/venv/security}"
SECURITY_REQUIREMENTS_FILE="${SECURITY_REQUIREMENTS_FILE:-./requirements/security/requirements-security.txt}"
SECURITY_CONFIG_DIR="${SECURITY_CONFIG_DIR:-./config/security}"
RUFF_CACHE_DIR="${RUFF_CACHE_DIR:-./artifacts/cache/ruff}"
PYTEST_CACHE_DIR="${PYTEST_CACHE_DIR:-./artifacts/cache/pytest}"
HYPOTHESIS_STORAGE_DIRECTORY="${HYPOTHESIS_STORAGE_DIRECTORY:-./artifacts/cache/hypothesis}"
SEMGREP_CONFIG_PATH="${SEMGREP_CONFIG_PATH:-${SECURITY_CONFIG_DIR}/semgrep.yml}"
BANDIT_CONFIG_PATH="${BANDIT_CONFIG_PATH:-${SECURITY_CONFIG_DIR}/bandit.yml}"
GITLEAKS_IGNORE_PATH="${GITLEAKS_IGNORE_PATH:-${SECURITY_CONFIG_DIR}/gitleaksignore}"
WRITE_TOKEN_PSA_ITEM="TELLER_CLASSIFIER_WRITE_TOKEN"

mkdir -p "$REPORT_DIR"
mkdir -p "$RUFF_CACHE_DIR" "$PYTEST_CACHE_DIR" "$HYPOTHESIS_STORAGE_DIRECTORY"
export RUFF_CACHE_DIR PYTEST_CACHE_DIR HYPOTHESIS_STORAGE_DIRECTORY

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
    echo "Install prerequisites with ./01_install_prerequisites.sh and pip install -r ${SECURITY_REQUIREMENTS_FILE}"
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
    echo "▶ Installing security toolchain into ${SECURITY_VENV_DIR}"
    "$security_pip" install --upgrade pip
    "$security_pip" install -r "$SECURITY_REQUIREMENTS_FILE"
  fi
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
    --exclude mutants,artifacts/security,artifacts/security-dast,.pytest_cache,.ruff_cache \
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
    "$dast_app_python" - <<'PY' "$integrity_report_path" "$seed_sql_path" "$strict_mode"
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
    match = re.search(
        r"SELECT\s+\*\s+FROM\s+\(VALUES(?P<rows>.*?)\)\s+AS\s+seed_rows\s*\(",
        sql_text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not match:
        raise ValueError("Could not locate canonical seed VALUES block in seed SQL.")

    rows_block = match.group("rows")
    row_count = len(re.findall(r"^\s*\(", rows_block, flags=re.MULTILINE))
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
    report["status"] = "error"
    report["gate_failed"] = strict_mode
    report["errors"].append(connect_error or "Database engine unavailable.")
    write_report(report)
    print(f"Category integrity report: {report_path}")
    print_failures(report)
    if strict_mode:
        print("❌ Post-DAST category integrity gate failed: database integrity could not be verified.")
        raise SystemExit(2)
    print("⚠️  Post-DAST category integrity checks skipped (non-strict mode).")
    raise SystemExit(0)

with engine.connect() as conn:
    # Invariant 1: IDs should stay in canonical seed range.
    unexpected_id_count = conn.exec_driver_sql(
        """
        SELECT COUNT(*)
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id < 1 OR nys_snw_category_id > %(canonical_max_id)s
        """,
        {"canonical_max_id": canonical_max_id},
    ).scalar_one()
    unexpected_id_rows = conn.exec_driver_sql(
        """
        SELECT nys_snw_category_id, level_1, level_2, level_3, categorization
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id < 1 OR nys_snw_category_id > %(canonical_max_id)s
         ORDER BY nys_snw_category_id
         LIMIT 20
        """,
        {"canonical_max_id": canonical_max_id},
    ).fetchall()
    append_invariant(
        report,
        "unexpected_category_ids",
        f"Category IDs must remain within canonical seed range [1, {canonical_max_id}].",
        unexpected_id_count,
        [serialize_row(row, ["nys_snw_category_id", "level_1", "level_2", "level_3", "categorization"]) for row in unexpected_id_rows],
    )

    # Invariant 2: Canonical IDs should not be missing.
    missing_id_count = conn.exec_driver_sql(
        """
        SELECT COUNT(*)
          FROM generate_series(1, %(canonical_max_id)s) AS expected_id
     LEFT JOIN teller.nys_snw_category c
            ON c.nys_snw_category_id = expected_id
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
         WHERE c.nys_snw_category_id IS NULL
         ORDER BY expected_id
         LIMIT 20
        """,
        {"canonical_max_id": canonical_max_id},
    ).fetchall()
    append_invariant(
        report,
        "missing_canonical_ids",
        "Canonical seed IDs should be present after DAST.",
        missing_id_count,
        [serialize_row(row, ["expected_id"]) for row in missing_id_rows],
    )

    # Invariant 3: No control / non-printable chars in hierarchy text.
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

    # Invariant 4: Rows cannot be completely empty across hierarchy text fields.
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

    # Invariant 5: Referential sanity for transaction category mappings.
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

repair_script = pathlib.Path("./src/scripts/repair_nys_snw_category.sql")
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
    python3 - <<'PY' "$source_openapi_url" "$source_base_url" "$output_schema_path" "$write_token"
import json
import sys
import urllib.parse
import urllib.request

openapi_url, base_url, out_path, write_token = sys.argv[1:5]

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
        }
    )
)
PY
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
  local base_url="${DAST_BASE_URL:-http://${base_host}:${base_port}}"
  local openapi_url="${DAST_OPENAPI_URL:-${base_url}/openapi.json}"

  local run_schemathesis="${RUN_SCHEMATHESIS:-true}"
  local run_zap="${RUN_ZAP:-true}"
  local reuse_existing_api="${DAST_REUSE_EXISTING_API:-${MACOS_UI_DAST_REUSE_EXISTING_API:-false}}"
  local run_token_capture_dast="${RUN_TOKEN_CAPTURE_DAST:-auto}" # true|false|auto
  local fail_on_high_critical="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
  local dast_write_token
  dast_write_token="$(read_classifier_write_token)"
  local zap_cli_cmd="${ZAP_CLI_CMD:-/Applications/ZAP.app/Contents/MacOS/ZAP.sh}"
  local zap_home_dir="${ZAP_HOME_DIR:-${SCRIPT_DIR}/artifacts/security/zap-home}"
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
      "$dast_app_python" "./21_run_classification_api.py" >"${report_dir_abs}/classification-api.log" 2>&1 &
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
    if prepare_schemathesis_openapi_fixture "$openapi_url" "$base_url" "$schemathesis_openapi_fixture" "$dast_write_token" \
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
  # Distinguish scanner findings from scanner execution failures.
  set +e
  bandit -r ./src/teller ./tests/py ./19_fetch_teller_api_data.py ./20_backfill_bank_statements.py ./21_run_classification_api.py \
    -c "$BANDIT_CONFIG_PATH" -f json -o "${REPORT_DIR}/bandit.json"
  BANDIT_EXIT=$?
  set -e
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
    --exclude-files '(^\.git/|^teller-venv/|^artifacts/venv/security/|^artifacts/security/|^artifacts/security-dast/|^artifacts/parallel/|^artifacts/mutation/|^artifacts/fuzz/|^artifacts/macos-ui-regression/|^artifacts/cache/ruff/|^artifacts/cache/pytest/|^artifacts/cache/hypothesis/|^artifacts/cache/egg-info/|^\.ruff_cache/|^\.pytest_cache/|^__pycache__/|^backups/|^archive/backup_extracts/|^archive/legacy/teller-connect-ui/|^config/bank_statements/|^src/macos-ui/\.derivedData-ui-tests/|^src/macos-ui/\.build/|^requirements/)' \
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
  python3 - <<'PY' "${REPORT_DIR}" "${FAIL_ON_MEDIUM_OR_HIGHER}"
import json
import sys
from pathlib import Path

report_dir = Path(sys.argv[1])
fail_on_medium_or_higher = sys.argv[2].lower() == "true"

semgrep_path = report_dir / "semgrep.json"
bandit_path = report_dir / "bandit.json"
pip_audit_path = report_dir / "pip-audit.json"
secrets_path = report_dir / "detect-secrets.json"
ruff_path = report_dir / "ruff.json"
swiftlint_path = report_dir / "swiftlint.json"
shellcheck_path = report_dir / "shellcheck.json"
gitleaks_path = report_dir / "gitleaks.json"

for required in [semgrep_path, bandit_path, pip_audit_path, secrets_path, ruff_path, swiftlint_path, shellcheck_path, gitleaks_path]:
    if not required.exists():
        print(f"Missing report file: {required}")
        sys.exit(1)

with semgrep_path.open("r", encoding="utf-8") as fh:
    semgrep = json.load(fh)
semgrep_results = semgrep.get("results", []) if isinstance(semgrep, dict) else []
semgrep_high = sum(1 for item in semgrep_results if item.get("extra", {}).get("severity") == "ERROR")
semgrep_total = len(semgrep_results)
semgrep_medium_or_higher = sum(
    1
    for item in semgrep_results
    if str(item.get("extra", {}).get("severity", "")).upper() in {"WARNING", "ERROR", "CRITICAL"}
)

with bandit_path.open("r", encoding="utf-8") as fh:
    bandit = json.load(fh)
bandit_results = bandit.get("results", []) if isinstance(bandit, dict) else []
bandit_high = sum(1 for item in bandit_results if item.get("issue_severity") == "HIGH")
bandit_medium_or_higher = sum(
    1
    for item in bandit_results
    if str(item.get("issue_severity", "")).upper() in {"MEDIUM", "HIGH"}
)
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

with ruff_path.open("r", encoding="utf-8") as fh:
    ruff = json.load(fh)
ruff_results = ruff if isinstance(ruff, list) else []
#R030: Enforce Ruff findings as blocking equivalents in SAST policy totals.
ruff_total = len(ruff_results)
ruff_high = ruff_total
ruff_medium_or_higher = ruff_total

with swiftlint_path.open("r", encoding="utf-8") as fh:
    swiftlint = json.load(fh)
swiftlint_results = swiftlint if isinstance(swiftlint, list) else []
swiftlint_high = sum(1 for item in swiftlint_results if str(item.get("severity", "")).lower() == "error")
swiftlint_medium_or_higher = sum(
    1 for item in swiftlint_results if str(item.get("severity", "")).lower() in {"warning", "error"}
)
swiftlint_total = len(swiftlint_results)

with shellcheck_path.open("r", encoding="utf-8") as fh:
    shellcheck = json.load(fh)
shellcheck_results = shellcheck if isinstance(shellcheck, list) else []
shellcheck_high = sum(1 for item in shellcheck_results if str(item.get("level", "")).lower() == "error")
shellcheck_medium_or_higher = sum(
    1 for item in shellcheck_results if str(item.get("level", "")).lower() in {"warning", "error"}
)
shellcheck_total = len(shellcheck_results)

with gitleaks_path.open("r", encoding="utf-8") as fh:
    gitleaks = json.load(fh)
if isinstance(gitleaks, list):
    gitleaks_findings = len(gitleaks)
elif isinstance(gitleaks, dict) and isinstance(gitleaks.get("findings"), list):
    gitleaks_findings = len(gitleaks.get("findings", []))
else:
    gitleaks_findings = 0

medium_or_higher_total = (
    semgrep_medium_or_higher
    + bandit_medium_or_higher
    + dep_vulns
    + secret_findings
    + ruff_medium_or_higher
    + swiftlint_medium_or_higher
    + shellcheck_medium_or_higher
    + gitleaks_findings
)
# Backward-compatible field retained for existing report consumers.
high_critical_total = medium_or_higher_total

summary = {
    "semgrep_total": semgrep_total,
    "semgrep_high_critical": semgrep_high,
    "semgrep_medium_or_higher": semgrep_medium_or_higher,
    "bandit_total": bandit_total,
    "bandit_high_critical": bandit_high,
    "bandit_medium_or_higher": bandit_medium_or_higher,
    "pip_audit_vulnerabilities": dep_vulns,
    "detect_secrets_findings": secret_findings,
    "ruff_total": ruff_total,
    "ruff_high_critical": ruff_high,
    "ruff_medium_or_higher": ruff_medium_or_higher,
    "shellcheck_total": shellcheck_total,
    "shellcheck_high_critical": shellcheck_high,
    "shellcheck_medium_or_higher": shellcheck_medium_or_higher,
    "gitleaks_findings": gitleaks_findings,
    "swiftlint_total": swiftlint_total,
    "swiftlint_high_critical": swiftlint_high,
    "swiftlint_medium_or_higher": swiftlint_medium_or_higher,
    "medium_or_higher_total": medium_or_higher_total,
    "high_critical_total": high_critical_total,
    "gate_policy": "financial-app-medium-or-higher-blocking",
    "gate_failed": fail_on_medium_or_higher and medium_or_higher_total > 0,
}

summary_path = report_dir / "sast-summary.json"
with summary_path.open("w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
    fh.write("\n")

print("Static Application Security Testing (SAST) summary")
print(json.dumps(summary, indent=2))

if fail_on_medium_or_higher and medium_or_higher_total > 0:
    print("❌ Static Application Security Testing (SAST) gate failed: Medium-or-higher findings detected.")
    sys.exit(1)
PY
  echo "✅ Static Application Security Testing (SAST) checks completed."
fi

if [[ "$RUN_DAST" == "true" ]]; then
  run_dast_checks "$REPORT_DIR"
fi

# Emit explicit completion status and artifact location for operators.
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
