#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R005: Execute from repository root regardless of caller directory.
cd "$SCRIPT_DIR"

#R010: Fixed checklist of nine numbered check scripts.
CHECKS=(
  "00_verify_requirements_traceability.sh"
  "04_run_dependency_freshness_checks.sh"
  "05_run_av_checks.sh"
  "06_run_sast.sh"
  "08_verify_deploy_database.sh"
  "09_run_unit_tests.sh"
  "10_run_macos_ui_regression_tests.sh"
  "11_verify_macos_crash_reporter.sh"
  "15_verify_classification_persistence.sh"
)

#R040: Remain a standalone meta-runner; child check scripts must not invoke this script.

#R035: Persist per-check stdout/stderr log artifacts.
REPORT_DIR="${PARALLEL_CHECKS_REPORT_DIR:-./.parallel-checks-reports}"
mkdir -p "$REPORT_DIR"
PROGRESS_INTERVAL_SECONDS="${PARALLEL_CHECKS_PROGRESS_INTERVAL_SECONDS:-1}"
if [[ ! "$PROGRESS_INTERVAL_SECONDS" =~ ^[0-9]+$ || "$PROGRESS_INTERVAL_SECONDS" -le 0 ]]; then
  PROGRESS_INTERVAL_SECONDS=1
fi
LOCK_FILE="${SCRIPT_DIR}/.18_run_all_checks_parallel.lock"
PROGRESS_INLINE=false
if [[ -t 1 ]]; then
  PROGRESS_INLINE=true
fi

#R050: Prevent concurrent invocations of this orchestrator from the same repo root.
release_single_run_lock() {
  local current_lock_pid=""
  if [[ -f "$LOCK_FILE" ]]; then
    current_lock_pid="$(<"$LOCK_FILE")"
    if [[ "$current_lock_pid" == "$$" ]]; then
      rm -f "$LOCK_FILE"
    fi
  fi
}

acquire_single_run_lock() {
  local existing_lock_pid=""
  if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi
  if [[ -f "$LOCK_FILE" ]]; then
    existing_lock_pid="$(<"$LOCK_FILE")"
  fi
  if [[ -n "$existing_lock_pid" ]] && kill -0 "$existing_lock_pid" 2>/dev/null; then
    echo "❌ FAIL: another 18_run_all_checks_parallel.sh run is already active (pid ${existing_lock_pid})." >&2
    return 1
  fi
  rm -f "$LOCK_FILE"
  if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi
  echo "❌ FAIL: unable to acquire single-run lock at ${LOCK_FILE}" >&2
  return 1
}

trap release_single_run_lock EXIT INT TERM
acquire_single_run_lock

render_progress() {
  local completed="$1"
  local total="$2"
  local bar_width=20
  local percent=0
  local filled=0
  local empty=0
  local filled_bar=""
  local empty_bar=""

  if [[ "$total" -gt 0 ]]; then
    percent=$((completed * 100 / total))
    filled=$((completed * bar_width / total))
  fi
  empty=$((bar_width - filled))
  filled_bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  empty_bar="$(printf '%*s' "$empty" '' | tr ' ' '-')"
  if [[ "$PROGRESS_INLINE" == "true" ]]; then
    printf '\r\033[2KProgress: [%s/%s (%s%%)] [%s%s]' "$completed" "$total" "$percent" "$filled_bar" "$empty_bar"
  else
    echo "Progress: [${completed}/${total} (${percent}%)] [${filled_bar}${empty_bar}]"
  fi
}

emit_result_line() {
  local message="$1"
  if [[ "$PROGRESS_INLINE" == "true" ]]; then
    # Clear the inline progress row before printing a completion line.
    printf '\r\033[2K'
  fi
  echo "$message"
}

finish_progress_line() {
  if [[ "$PROGRESS_INLINE" == "true" ]]; then
    printf '\n'
  fi
}

for script in "${CHECKS[@]}"; do
  if [[ ! -f "./${script}" ]]; then
    echo "❌ FAIL: expected check script not found: ./${script}" >&2
    exit 1
  fi
done

echo "▶ Starting parallel checks (${#CHECKS[@]} scripts)..."

COMPLETION_FIFO="${REPORT_DIR}/.completion.fifo"
rm -f "$COMPLETION_FIFO"
mkfifo "$COMPLETION_FIFO"
exec 3<> "$COMPLETION_FIFO"

#R015: Launch all check scripts concurrently.
#R020: Capture each child exit code independently.
pids=()
for script in "${CHECKS[@]}"; do
  log="${REPORT_DIR}/${script%.sh}.log"
  rm -f "${log}" "${log}.exit"
  (
    set +e
    "./${script}" >"${log}" 2>&1
    exit_code=$?
    echo "$exit_code" > "${log}.exit"
    printf '%s|%s\n' "$script" "$exit_code" >&3
  ) &
  pids+=("$!")
done

#R025: Print each pass/fail line as soon as its check completes (completion order).
pass_count=0
fail_count=0
total="${#CHECKS[@]}"
reported=0

#R045: Emit continuous aggregate progress while checks are still running.
render_progress "$reported" "$total"
while [[ "$reported" -lt "$total" ]]; do
  if IFS='|' read -r -t "$PROGRESS_INTERVAL_SECONDS" completed_script completed_exit <&3; then
    reported=$((reported + 1))
    log="${REPORT_DIR}/${completed_script%.sh}.log"
    if [[ "$completed_exit" -eq 0 ]]; then
      emit_result_line "✅ PASS: ${completed_script}"
      pass_count=$((pass_count + 1))
    else
      emit_result_line "❌ FAIL: ${completed_script} (exit ${completed_exit}) — see ${log}"
      fail_count=$((fail_count + 1))
    fi
  fi

  render_progress "$reported" "$total"
done
exec 3>&-
finish_progress_line

set +e
for pid in "${pids[@]}"; do
  wait "$pid"
done
set -e

#R030: Print overall pass/fail gate and exit code.
if [[ "$fail_count" -eq 0 ]]; then
  echo "✅ PASS: all parallel checks succeeded (${pass_count}/${total})"
  exit 0
fi

echo "❌ FAIL: parallel checks: ${pass_count}/${total} passed"
exit 1
