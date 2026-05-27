#!/usr/bin/env bash
umask 007
#R001: Run in strict shell mode from repository root.
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "$REPO_ROOT"

#R005: Support configurable quality reports, targets, and gating behavior.
REPORT_DIR="${QUALITY_REPORT_DIR:-./artifacts/quality/reports}"
QUALITY_TARGETS="${QUALITY_TARGETS:-./src/teller ./src/scripts ./tests}"
FAIL_ON_QUALITY_ISSUES="${FAIL_ON_QUALITY_ISSUES:-true}"
RUN_VULTURE="${RUN_VULTURE:-true}"
RUN_RADON="${RUN_RADON:-true}"
RUN_XENON="${RUN_XENON:-true}"
VULTURE_MIN_CONFIDENCE="${VULTURE_MIN_CONFIDENCE:-80}"
RADON_EXCLUDE="${RADON_EXCLUDE:-.venv,venv,teller-venv,artifacts}"
XENON_MAX_ABSOLUTE="${XENON_MAX_ABSOLUTE:-B}"
XENON_MAX_MODULES="${XENON_MAX_MODULES:-B}"
XENON_MAX_AVERAGE="${XENON_MAX_AVERAGE:-A}"

mkdir -p "$REPORT_DIR"

read -r -a QUALITY_TARGETS_ARR <<< "$QUALITY_TARGETS"
if [[ "${#QUALITY_TARGETS_ARR[@]}" -eq 0 ]]; then
  echo "ERROR: no quality targets configured."
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1"
    echo "Run ./03_load_requirements.sh to install project Python tooling."
    exit 1
  fi
}

print_tool_header() {
  local tool_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local tool_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Quality Tool: ${tool_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${tool_url}"
  printf '%s\n' "$border"
}

count_nonempty_lines() {
  local path="$1"
  awk 'NF { count += 1 } END { print count + 0 }' "$path"
}

print_report_details() {
  local label="$1"
  local path="$2"
  local max_lines="${3:-40}"
  if [[ ! -f "$path" ]]; then
    return
  fi
  if ! awk 'NF { found=1; exit 0 } END { exit found ? 0 : 1 }' "$path"; then
    return
  fi
  echo "${label} details:"
  awk -v limit="$max_lines" 'NF { print; count += 1; if (count >= limit) exit }' "$path"
}

vulture_exit=0
radon_exit=0
xenon_exit=0
vulture_gate_failed=false
xenon_gate_failed=false

#R010: Run Vulture dead-code scanning and optionally gate on findings.
if [[ "$RUN_VULTURE" == "true" ]]; then
  require_command vulture
  print_tool_header \
    "Vulture" \
    "Finds likely dead Python code using static analysis." \
    "Highlights unused functions, classes, imports, and variables." \
    "https://github.com/jendrikseipp/vulture"
  set +e
  vulture "${QUALITY_TARGETS_ARR[@]}" --min-confidence "$VULTURE_MIN_CONFIDENCE" > "${REPORT_DIR}/vulture.txt" 2>&1
  vulture_exit=$?
  set -e
  if [[ "$vulture_exit" -ne 0 && "$vulture_exit" -ne 1 && "$vulture_exit" -ne 3 ]]; then
    echo "ERROR: Vulture failed to execute."
    exit 1
  fi
  vulture_findings="$(count_nonempty_lines "${REPORT_DIR}/vulture.txt")"
  echo "INFO: Vulture detailed status: exit_code=${vulture_exit}; findings=${vulture_findings}; report=${REPORT_DIR}/vulture.txt"
  #R025: Print actionable quality details to console so users do not need to open report files.
  print_report_details "Vulture" "${REPORT_DIR}/vulture.txt" 60
  if [[ "$vulture_exit" -eq 1 || "$vulture_exit" -eq 3 ]] && [[ "$FAIL_ON_QUALITY_ISSUES" == "true" ]]; then
    vulture_gate_failed=true
  fi
else
  printf 'skipped\n' > "${REPORT_DIR}/vulture.txt"
fi

#R015: Run Radon cyclomatic-complexity analysis and emit a report.
if [[ "$RUN_RADON" == "true" ]]; then
  require_command radon
  print_tool_header \
    "Radon" \
    "Reports Python cyclomatic complexity and maintainability metrics." \
    "Helps identify code that needs decomposition or refactoring." \
    "https://radon.readthedocs.io/"
  set +e
  radon cc "${QUALITY_TARGETS_ARR[@]}" -s -a --exclude "$RADON_EXCLUDE" > "${REPORT_DIR}/radon.txt" 2>&1
  radon_exit=$?
  set -e
  if [[ "$radon_exit" -ne 0 ]]; then
    echo "ERROR: Radon failed to execute."
    exit 1
  fi
  radon_lines="$(count_nonempty_lines "${REPORT_DIR}/radon.txt")"
  echo "INFO: Radon detailed status: exit_code=${radon_exit}; lines=${radon_lines}; report=${REPORT_DIR}/radon.txt"
  print_report_details "Radon" "${REPORT_DIR}/radon.txt" 80
else
  printf 'skipped\n' > "${REPORT_DIR}/radon.txt"
fi

#R020: Run Xenon complexity gate checks and enforce configurable thresholds.
if [[ "$RUN_XENON" == "true" ]]; then
  require_command xenon
  print_tool_header \
    "Xenon" \
    "Enforces complexity thresholds over Radon code metrics." \
    "Fails quality gates when complexity exceeds configured limits." \
    "https://github.com/rubik/xenon"
  set +e
  xenon \
    --max-absolute "$XENON_MAX_ABSOLUTE" \
    --max-modules "$XENON_MAX_MODULES" \
    --max-average "$XENON_MAX_AVERAGE" \
    "${QUALITY_TARGETS_ARR[@]}" > "${REPORT_DIR}/xenon.txt" 2>&1
  xenon_exit=$?
  set -e
  if [[ "$xenon_exit" -gt 1 ]]; then
    echo "ERROR: Xenon failed to execute."
    exit 1
  fi
  echo "INFO: Xenon detailed status: exit_code=${xenon_exit}; report=${REPORT_DIR}/xenon.txt"
  print_report_details "Xenon" "${REPORT_DIR}/xenon.txt" 80
  if [[ "$xenon_exit" -eq 1 ]] && [[ "$FAIL_ON_QUALITY_ISSUES" == "true" ]]; then
    xenon_gate_failed=true
  fi
else
  printf 'skipped\n' > "${REPORT_DIR}/xenon.txt"
fi

python3 - <<'PY' "${REPORT_DIR}/code-quality-summary.json" "$vulture_exit" "$radon_exit" "$xenon_exit" "$vulture_gate_failed" "$xenon_gate_failed"
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
vulture_exit = int(sys.argv[2])
radon_exit = int(sys.argv[3])
xenon_exit = int(sys.argv[4])
vulture_gate_failed = sys.argv[5].lower() == "true"
xenon_gate_failed = sys.argv[6].lower() == "true"

payload = {
    "vulture_exit": vulture_exit,
    "radon_exit": radon_exit,
    "xenon_exit": xenon_exit,
    "vulture_gate_failed": vulture_gate_failed,
    "xenon_gate_failed": xenon_gate_failed,
    "gate_failed": vulture_gate_failed or xenon_gate_failed,
}
summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

if [[ "$vulture_gate_failed" == "true" ]] || [[ "$xenon_gate_failed" == "true" ]]; then
  echo "ERROR: Code quality gate failed."
  exit 1
fi

echo "PASS: Code quality checks completed. Reports: ${REPORT_DIR}"
