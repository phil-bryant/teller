#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R005: Execute from repository root regardless of caller directory.
cd "$SCRIPT_DIR"

#R010: Discover numbered check scripts dynamically by basename.
SELF_SCRIPT_BASENAME="$(basename "${BASH_SOURCE[0]}")"
CHECKS=()
for candidate in ./*.sh; do
  script="$(basename "$candidate")"
  if [[ "$script" == "$SELF_SCRIPT_BASENAME" ]]; then
    continue
  fi
  if [[ "$script" =~ ^[0-9]{2}_.*$ && "$script" =~ (^|_)tests?(_|\.sh$) ]]; then
    CHECKS+=("$script")
  fi
done

if [[ "${#CHECKS[@]}" -eq 0 ]]; then
  echo "❌ FAIL: no numbered test scripts found (expected names containing test or tests)." >&2
  exit 1
fi

#R040: Remain a standalone meta-runner; child check scripts must not invoke this script.

#R035: Persist per-check stdout/stderr log artifacts.
REPORT_DIR="${PARALLEL_CHECKS_REPORT_DIR:-./.parallel-checks-reports}"
mkdir -p "$REPORT_DIR"
PROGRESS_INTERVAL_SECONDS="${PARALLEL_CHECKS_PROGRESS_INTERVAL_SECONDS:-1}"
if [[ ! "$PROGRESS_INTERVAL_SECONDS" =~ ^[0-9]+$ || "$PROGRESS_INTERVAL_SECONDS" -le 0 ]]; then
  PROGRESS_INTERVAL_SECONDS=1
fi
LOCK_FILE="${SCRIPT_DIR}/.22_run_all_tests_parallel.lock"
PROGRESS_INLINE=false
if [[ -t 1 ]]; then
  PROGRESS_INLINE=true
fi
child_pids=()
cleanup_finished=false
signal_exit_code=""

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
    echo "❌ FAIL: another 22_run_all_tests_parallel.sh run is already active (pid ${existing_lock_pid})." >&2
    return 1
  fi
  rm -f "$LOCK_FILE"
  if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi
  echo "❌ FAIL: unable to acquire single-run lock at ${LOCK_FILE}" >&2
  return 1
}

#R055: Terminate launched child checks on interrupt or termination.
terminate_child_checks() {
  local pid child grandchild
  for pid in "${child_pids[@]}"; do
    [[ -n "$pid" ]] || continue
    kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
      kill -TERM "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null || true
      for grandchild in $(pgrep -P "$child" 2>/dev/null || true); do
        kill -TERM "$grandchild" 2>/dev/null || true
      done
    done
  done

  sleep 1

  for pid in "${child_pids[@]}"; do
    [[ -n "$pid" ]] || continue
    kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
      kill -KILL "-$child" 2>/dev/null || kill -KILL "$child" 2>/dev/null || true
      for grandchild in $(pgrep -P "$child" 2>/dev/null || true); do
        kill -KILL "$grandchild" 2>/dev/null || true
      done
    done
  done
}

finish_run_cleanup() {
  if [[ "$cleanup_finished" == "true" ]]; then
    return 0
  fi
  cleanup_finished=true
  finish_progress_line
  release_single_run_lock
}

stop_on_signal() {
  local exit_code="$1"
  if [[ "$cleanup_finished" == "true" ]]; then
    exit "$exit_code"
  fi
  cleanup_finished=true
  terminate_child_checks
  finish_progress_line
  echo "Interrupted; stopped parallel checks." >&2
  release_single_run_lock
  exit "$exit_code"
}

check_for_signal() {
  if [[ -n "$signal_exit_code" ]]; then
    stop_on_signal "$signal_exit_code"
  fi
}

record_sigint() {
  signal_exit_code=130
}

record_sigterm() {
  signal_exit_code=143
}

trap finish_run_cleanup EXIT
trap record_sigint INT
trap record_sigterm TERM
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

#R060: Record orchestrator wall-clock start for long-pole timing.
run_start_epoch="$(date +%s)"
long_pole_script=""
long_pole_seconds=0

#R015: Launch all check scripts concurrently.
#R020: Capture each child exit code independently.
for script in "${CHECKS[@]}"; do
  log="${REPORT_DIR}/${script%.sh}.log"
  rm -f "${log}" "${log}.exit" "${log}.exit.reported" "${log}.start"
  date +%s > "${log}.start"
  (
    set +e
    "./${script}" >"${log}" 2>&1
    exit_code=$?
    echo "$exit_code" > "${log}.exit"
  ) &
  child_pids+=("$!")
done

if [[ "${PARALLEL_CHECKS_TEST_INTERRUPT:-}" == "1" ]]; then
  stop_on_signal 130
fi

#R025: Print each pass/fail line as soon as its check completes (completion order).
pass_count=0
fail_count=0
total="${#CHECKS[@]}"
reported=0

#R045: Emit continuous aggregate progress while checks are still running.
render_progress "$reported" "$total"
while [[ "$reported" -lt "$total" ]]; do
  check_for_signal
  for script in "${CHECKS[@]}"; do
    exit_file="${REPORT_DIR}/${script%.sh}.log.exit"
    reported_file="${exit_file}.reported"
    if [[ ! -f "$exit_file" || -f "$reported_file" ]]; then
      continue
    fi
    : >"$reported_file"
    reported=$((reported + 1))
    log="${REPORT_DIR}/${script%.sh}.log"
    start_file="${log}.start"
    start_epoch=0
    if [[ -f "$start_file" ]]; then
      start_epoch="$(<"$start_file")"
    fi
    elapsed=0
    if [[ "$start_epoch" -gt 0 ]]; then
      elapsed=$(( $(date +%s) - start_epoch ))
    fi
    completed_exit="$(<"$exit_file")"
    if [[ "$elapsed" -gt "$long_pole_seconds" ]]; then
      long_pole_seconds="$elapsed"
      long_pole_script="$script"
    fi
    if [[ "$completed_exit" -eq 0 ]]; then
      emit_result_line "✅ PASS: ${script} (${elapsed}s)"
      pass_count=$((pass_count + 1))
    else
      emit_result_line "❌ FAIL: ${script} (exit ${completed_exit}, ${elapsed}s) — see ${log}"
      fail_count=$((fail_count + 1))
    fi
  done
  check_for_signal
  render_progress "$reported" "$total"
  if [[ "$reported" -lt "$total" ]]; then
    sleep "$PROGRESS_INTERVAL_SECONDS"
  fi
done

set +e
for pid in "${child_pids[@]}"; do
  wait "$pid"
done
set -e

#R060: Report wall time and longest lane before overall gate.
wall_elapsed=$(( $(date +%s) - run_start_epoch ))
echo "Timing: wall ${wall_elapsed}s; long pole ${long_pole_script} (${long_pole_seconds}s)"

#R030: Print overall pass/fail gate and exit code.
if [[ "$fail_count" -eq 0 ]]; then
  echo "✅ PASS: all parallel checks succeeded (${pass_count}/${total})"
  exit 0
fi

echo "❌ FAIL: parallel checks: ${pass_count}/${total} passed"
exit 1
