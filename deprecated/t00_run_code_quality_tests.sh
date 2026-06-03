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

#R005: Prefer project venv tooling when available so quality runners are reproducible.
if [[ -d "${REPO_ROOT}/teller-venv/bin" ]]; then
  export PATH="${REPO_ROOT}/teller-venv/bin:${PATH}"
fi

#R005: Support configurable quality reports, targets, and gating behavior.
REPORT_DIR="${QUALITY_REPORT_DIR:-./artifacts/quality/reports}"
QUALITY_TARGETS="${QUALITY_TARGETS:-./src/teller ./src/scripts ./tests/sh}"
FAIL_ON_QUALITY_ISSUES="${FAIL_ON_QUALITY_ISSUES:-true}"
RUN_VULTURE="${RUN_VULTURE:-true}"
RUN_RADON="${RUN_RADON:-true}"
RUN_XENON="${RUN_XENON:-true}"
RUN_PERIPHERY="${RUN_PERIPHERY:-true}"
RUN_LIZARD="${RUN_LIZARD:-true}"
VULTURE_MIN_CONFIDENCE="${VULTURE_MIN_CONFIDENCE:-80}"
RADON_EXCLUDE="${RADON_EXCLUDE:-.venv,venv,teller-venv,artifacts}"
XENON_MAX_ABSOLUTE="${XENON_MAX_ABSOLUTE:-C}"
XENON_MAX_MODULES="${XENON_MAX_MODULES:-B}"
XENON_MAX_AVERAGE="${XENON_MAX_AVERAGE:-A}"
PERIPHERY_PROJECT_DIR="${PERIPHERY_PROJECT_DIR:-./src/macos-ui}"
# Default extra args reduce Codable/public/ObjC false positives in SwiftUI + AppKit projects,
# so the findings that surface are real (no blanket suppression).
PERIPHERY_EXTRA_ARGS="${PERIPHERY_EXTRA_ARGS:---retain-codable-properties --retain-public --retain-objc-accessible}"
# Gate modes: `warn` reports findings without failing the lane; `block` honors FAIL_ON_QUALITY_ISSUES.
# Default `block` because this is a financial application: dead code and undetected complexity are real risks.
PERIPHERY_GATE_MODE="${PERIPHERY_GATE_MODE:-block}"
LIZARD_TARGETS="${LIZARD_TARGETS:-./src/macos-ui/Sources ./src/macos-ui/Tests}"
# Strict defaults (industry conventional) for a financial app: keep functions small and obvious.
LIZARD_CCN_THRESHOLD="${LIZARD_CCN_THRESHOLD:-10}"
LIZARD_LENGTH_THRESHOLD="${LIZARD_LENGTH_THRESHOLD:-60}"
LIZARD_ARG_THRESHOLD="${LIZARD_ARG_THRESHOLD:-5}"
LIZARD_GATE_MODE="${LIZARD_GATE_MODE:-block}"

mkdir -p "$REPORT_DIR"

read -r -a QUALITY_TARGETS_ARR <<< "$QUALITY_TARGETS"
if [[ "${#QUALITY_TARGETS_ARR[@]}" -eq 0 ]]; then
  echo "ERROR: no quality targets configured."
  exit 1
fi

read -r -a LIZARD_TARGETS_ARR <<< "$LIZARD_TARGETS"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1"
    echo "Run ./04_load_requirements.sh to install project Python tooling."
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
periphery_exit=0
lizard_exit=0
vulture_gate_failed=false
xenon_gate_failed=false
periphery_gate_failed=false
lizard_gate_failed=false

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

#R030: Run Periphery dead-code scanning on Swift sources and gate on findings.
if [[ "$RUN_PERIPHERY" == "true" ]]; then
  require_command periphery
  print_tool_header \
    "Periphery" \
    "Finds likely dead Swift code (Vulture analog for Swift)." \
    "Reports unused declarations, parameters, properties, and protocols." \
    "https://github.com/peripheryapp/periphery"
  set +e
  (
    if [[ -n "$PERIPHERY_PROJECT_DIR" && "$PERIPHERY_PROJECT_DIR" != "." ]]; then
      cd "$PERIPHERY_PROJECT_DIR" || exit 127
    fi
    # shellcheck disable=SC2086
    periphery scan --strict $PERIPHERY_EXTRA_ARGS
  ) > "${REPORT_DIR}/periphery.txt" 2>&1
  periphery_exit=$?
  set -e
  if [[ "$periphery_exit" -eq 127 ]]; then
    echo "ERROR: Periphery project directory not found: ${PERIPHERY_PROJECT_DIR}"
    exit 1
  fi
  if [[ "$periphery_exit" -ne 0 && "$periphery_exit" -ne 1 ]]; then
    echo "ERROR: Periphery failed to execute."
    exit 1
  fi
  periphery_findings="$(count_nonempty_lines "${REPORT_DIR}/periphery.txt")"
  echo "INFO: Periphery detailed status: exit_code=${periphery_exit}; lines=${periphery_findings}; report=${REPORT_DIR}/periphery.txt"
  print_report_details "Periphery" "${REPORT_DIR}/periphery.txt" 60
  if [[ "$periphery_exit" -eq 1 ]] && [[ "$FAIL_ON_QUALITY_ISSUES" == "true" ]] && [[ "$PERIPHERY_GATE_MODE" == "block" ]]; then
    periphery_gate_failed=true
  fi
else
  printf 'skipped\n' > "${REPORT_DIR}/periphery.txt"
fi

#R035: Run Lizard cyclomatic-complexity analysis on Swift sources and gate on threshold violations.
if [[ "$RUN_LIZARD" == "true" ]]; then
  require_command lizard
  print_tool_header \
    "Lizard" \
    "Reports Swift cyclomatic complexity and enforces thresholds (Radon+Xenon analog)." \
    "Highlights overly complex, long, or wide-parameter functions in Swift code." \
    "https://github.com/terryyin/lizard"
  set +e
  lizard \
    -l swift \
    --CCN "$LIZARD_CCN_THRESHOLD" \
    --length "$LIZARD_LENGTH_THRESHOLD" \
    --arguments "$LIZARD_ARG_THRESHOLD" \
    "${LIZARD_TARGETS_ARR[@]}" > "${REPORT_DIR}/lizard.txt" 2>&1
  lizard_exit=$?
  set -e
  if [[ "$lizard_exit" -ne 0 && "$lizard_exit" -ne 1 ]]; then
    echo "ERROR: Lizard failed to execute."
    exit 1
  fi
  lizard_lines="$(count_nonempty_lines "${REPORT_DIR}/lizard.txt")"
  echo "INFO: Lizard detailed status: exit_code=${lizard_exit}; lines=${lizard_lines}; report=${REPORT_DIR}/lizard.txt"
  print_report_details "Lizard" "${REPORT_DIR}/lizard.txt" 80
  if [[ "$lizard_exit" -eq 1 ]] && [[ "$FAIL_ON_QUALITY_ISSUES" == "true" ]] && [[ "$LIZARD_GATE_MODE" == "block" ]]; then
    lizard_gate_failed=true
  fi
else
  printf 'skipped\n' > "${REPORT_DIR}/lizard.txt"
fi

python3 - <<'PY' "${REPORT_DIR}/code-quality-summary.json" "$vulture_exit" "$radon_exit" "$xenon_exit" "$periphery_exit" "$lizard_exit" "$vulture_gate_failed" "$xenon_gate_failed" "$periphery_gate_failed" "$lizard_gate_failed"
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
vulture_exit = int(sys.argv[2])
radon_exit = int(sys.argv[3])
xenon_exit = int(sys.argv[4])
periphery_exit = int(sys.argv[5])
lizard_exit = int(sys.argv[6])
vulture_gate_failed = sys.argv[7].lower() == "true"
xenon_gate_failed = sys.argv[8].lower() == "true"
periphery_gate_failed = sys.argv[9].lower() == "true"
lizard_gate_failed = sys.argv[10].lower() == "true"

payload = {
    "vulture_exit": vulture_exit,
    "radon_exit": radon_exit,
    "xenon_exit": xenon_exit,
    "periphery_exit": periphery_exit,
    "lizard_exit": lizard_exit,
    "vulture_gate_failed": vulture_gate_failed,
    "xenon_gate_failed": xenon_gate_failed,
    "periphery_gate_failed": periphery_gate_failed,
    "lizard_gate_failed": lizard_gate_failed,
    "gate_failed": (
        vulture_gate_failed
        or xenon_gate_failed
        or periphery_gate_failed
        or lizard_gate_failed
    ),
}
summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

if [[ "$vulture_gate_failed" == "true" ]] \
  || [[ "$xenon_gate_failed" == "true" ]] \
  || [[ "$periphery_gate_failed" == "true" ]] \
  || [[ "$lizard_gate_failed" == "true" ]]; then
  echo "ERROR: Code quality gate failed."
  exit 1
fi

echo "PASS: Code quality checks completed. Reports: ${REPORT_DIR}"
