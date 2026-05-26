#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Execute from repository root regardless of caller directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MACOS_UI_DIR="${MACOS_UI_DIR:-./src/macos-ui}"
CRASH_REPORT_DIR="${CRASH_REPORT_DIR:-${HOME}/Library/Application Support/TransactionClassifier/CrashReports}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-20}"
TIMEOUT_HELPER_PYTHON="${TIMEOUT_HELPER_PYTHON:-python3}"
MACOS_UI_SWIFTPM_LOCK="${MACOS_UI_SWIFTPM_LOCK:-${MACOS_UI_DIR}/.swiftpm-run.lock}"
MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS="${MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS:-45}"
CRASH_LAUNCH_TIMEOUT_SECONDS="${CRASH_LAUNCH_TIMEOUT_SECONDS:-45}"
PREWARM_BUILD_TIMEOUT_SECONDS="${PREWARM_BUILD_TIMEOUT_SECONDS:-180}"
LAUNCH_LOG="$(mktemp)"
RECOVERY_LOG="$(mktemp)"
PREWARM_LOG="$(mktemp)"
UNCLEAN_LOG="$(mktemp)"
UNCLEAN_MARKER_FILE_NAME="${UNCLEAN_MARKER_FILE_NAME:-session-active.json}"
MARKER_FILE="$(mktemp)"
UNCLEAN_MARKER_TIMESTAMP_FILE="$(mktemp)"
latest_plcrash=""
latest_json=""
latest_unclean_json=""
baseline_plcrash=""
baseline_json=""
baseline_unclean_json=""
relaunch_saw_persistence_log=0
relaunch_saw_unclean_log=0
#R040: This script remains a standalone numbered entrypoint (not chained by other numbered runners).

#R030: Fail clearly when required local tooling is unavailable.
if ! command -v swift >/dev/null 2>&1; then
  echo "❌ swift is required for PLCrashReporter verification."
  exit 1
fi

if [[ ! -d "$MACOS_UI_DIR" ]]; then
  echo "❌ macOS UI package path not found at ${MACOS_UI_DIR}."
  exit 1
fi

MACOS_UI_SWIFT_LOCK_HELPER="./src/scripts/macos_ui_swift_lock.sh"
if [[ ! -f "$MACOS_UI_SWIFT_LOCK_HELPER" ]]; then
  echo "❌ macOS UI SwiftPM lock helper not found at ${MACOS_UI_SWIFT_LOCK_HELPER}."
  exit 1
fi
# shellcheck disable=SC1090
source "$MACOS_UI_SWIFT_LOCK_HELPER"

mkdir -p "$CRASH_REPORT_DIR"

run_with_timeout() {
  local timeout_seconds="$1"
  local timeout_label="$2"
  shift 2
  if ! command -v "$TIMEOUT_HELPER_PYTHON" >/dev/null 2>&1; then
    echo "❌ ${TIMEOUT_HELPER_PYTHON} is required to enforce timeout for ${timeout_label}."
    return 1
  fi
  local had_errexit=0
  if [[ "$-" == *e* ]]; then
    had_errexit=1
  fi
  set +e
  "$TIMEOUT_HELPER_PYTHON" - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
command = sys.argv[2:]
if timeout_seconds <= 0:
    timeout_seconds = 1

proc = subprocess.Popen(command, preexec_fn=os.setsid)
try:
    proc.wait(timeout=timeout_seconds)
    raise SystemExit(proc.returncode)
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
    raise SystemExit(124)
PY
  local status=$?
  if [[ "$had_errexit" -eq 1 ]]; then
    set -e
  else
    set +e
  fi
  return "$status"
}

terminate_process_tree() {
  local root_pid="$1"
  local child_pid=""

  if [[ -z "$root_pid" ]] || ! kill -0 "$root_pid" >/dev/null 2>&1; then
    return 0
  fi

  while IFS= read -r child_pid; do
    terminate_process_tree "$child_pid"
  done < <(pgrep -P "$root_pid" 2>/dev/null || true)

  kill "$root_pid" >/dev/null 2>&1 || true
  sleep 0.2
  if kill -0 "$root_pid" >/dev/null 2>&1; then
    kill -9 "$root_pid" >/dev/null 2>&1 || true
  fi
}

run_relaunch() {
  local relaunch_pid=""
  local timed_out=0
  local second=0

  relaunch_saw_persistence_log=0
  : > "$LAUNCH_LOG"

  bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
    "$MACOS_UI_SWIFT_LOCK_HELPER" \
    "$MACOS_UI_SWIFTPM_LOCK" \
    "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
    "17_verify_macos_crash_test:relaunch" \
    sh -c "cd \"\$1\" && swift run TransactionClassifier" _ "$MACOS_UI_DIR" >"$LAUNCH_LOG" 2>&1 &
  relaunch_pid=$!

  #R050: Poll relaunch output and stop once persistence log appears.
  for ((second=1; second<=STARTUP_WAIT_SECONDS; second++)); do
    if grep -q "CrashReporter: saved pending crash report to" "$LAUNCH_LOG"; then
      relaunch_saw_persistence_log=1
      break
    fi
    if ! kill -0 "$relaunch_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if kill -0 "$relaunch_pid" >/dev/null 2>&1; then
    if [[ "$relaunch_saw_persistence_log" -eq 1 ]]; then
      terminate_process_tree "$relaunch_pid"
    else
      timed_out=1
      terminate_process_tree "$relaunch_pid"
    fi
  fi
  wait "$relaunch_pid" >/dev/null 2>&1 || true

  if [[ "$relaunch_saw_persistence_log" -ne 1 ]] &&
     grep -q "CrashReporter: saved pending crash report to" "$LAUNCH_LOG"; then
    relaunch_saw_persistence_log=1
  fi

  #R050: Return timeout when persistence log is absent at deadline.
  if [[ "$relaunch_saw_persistence_log" -eq 1 ]]; then
    return 0
  fi
  if [[ "$timed_out" -eq 1 ]]; then
    return 124
  fi
  return 1
}

run_unclean_marker_relaunch() {
  local relaunch_pid=""
  local timed_out=0
  local second=0

  relaunch_saw_unclean_log=0
  : > "$UNCLEAN_LOG"

  bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
    "$MACOS_UI_SWIFT_LOCK_HELPER" \
    "$MACOS_UI_SWIFTPM_LOCK" \
    "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
    "17_verify_macos_crash_test:unclean-relaunch" \
    sh -c "cd \"\$1\" && swift run TransactionClassifier" _ "$MACOS_UI_DIR" >"$UNCLEAN_LOG" 2>&1 &
  relaunch_pid=$!

  #R065: Poll relaunch output and stop once unclean-termination marker persistence appears.
  for ((second=1; second<=STARTUP_WAIT_SECONDS; second++)); do
    if grep -q "CrashReporter: saved unclean termination marker to" "$UNCLEAN_LOG"; then
      relaunch_saw_unclean_log=1
      break
    fi
    if ! kill -0 "$relaunch_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if kill -0 "$relaunch_pid" >/dev/null 2>&1; then
    if [[ "$relaunch_saw_unclean_log" -eq 1 ]]; then
      terminate_process_tree "$relaunch_pid"
    else
      timed_out=1
      terminate_process_tree "$relaunch_pid"
    fi
  fi
  wait "$relaunch_pid" >/dev/null 2>&1 || true

  if [[ "$relaunch_saw_unclean_log" -ne 1 ]] &&
     grep -q "CrashReporter: saved unclean termination marker to" "$UNCLEAN_LOG"; then
    relaunch_saw_unclean_log=1
  fi

  if [[ "$relaunch_saw_unclean_log" -eq 1 ]]; then
    return 0
  fi
  if [[ "$timed_out" -eq 1 ]]; then
    return 124
  fi
  return 1
}

recover_swiftpm_state() {
  #R045: Rebuild SwiftPM state after stale checkout metadata errors.
  run_with_timeout "$CRASH_LAUNCH_TIMEOUT_SECONDS" "macOS SwiftPM state recovery" \
    bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
      "$MACOS_UI_SWIFT_LOCK_HELPER" \
      "$MACOS_UI_SWIFTPM_LOCK" \
      "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
      "17_verify_macos_crash_test:swiftpm-recovery" \
      sh -c "cd \"\$1\" && rm -rf .build && swift package resolve" _ "$MACOS_UI_DIR" >"$RECOVERY_LOG" 2>&1
}

prewarm_swiftpm_build() {
  #R060: Warm the TransactionClassifier build once so relaunch timeout measures startup, not cold compile.
  run_with_timeout "$PREWARM_BUILD_TIMEOUT_SECONDS" "macOS prewarm build" \
    bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
      "$MACOS_UI_SWIFT_LOCK_HELPER" \
      "$MACOS_UI_SWIFTPM_LOCK" \
      "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
      "17_verify_macos_crash_test:prewarm-build" \
      sh -c "cd \"\$1\" && swift build --product TransactionClassifier" _ "$MACOS_UI_DIR" >"$PREWARM_LOG" 2>&1
}

refresh_latest_unclean_artifact() {
  shopt -s nullglob
  local unclean_files=("$CRASH_REPORT_DIR"/unclean-exit-*.json)
  shopt -u nullglob

  latest_unclean_json=""
  if [[ "${#unclean_files[@]}" -eq 0 ]]; then
    return
  fi

  latest_unclean_json="${unclean_files[0]}"
  for candidate in "${unclean_files[@]}"; do
    if [[ "$candidate" -nt "$latest_unclean_json" ]]; then
      latest_unclean_json="$candidate"
    fi
  done
}

unclean_artifact_is_fresh() {
  if [[ -z "$latest_unclean_json" ]]; then
    return 1
  fi

  if [[ -n "$baseline_unclean_json" && "$latest_unclean_json" != "$baseline_unclean_json" ]]; then
    return 0
  fi

  [[ "$latest_unclean_json" -nt "$UNCLEAN_MARKER_TIMESTAMP_FILE" ]]
}

refresh_latest_artifacts() {
  shopt -s nullglob
  local plcrash_files=("$CRASH_REPORT_DIR"/*.plcrash)
  local json_files=("$CRASH_REPORT_DIR"/*.json)
  shopt -u nullglob

  latest_plcrash=""
  latest_json=""
  if [[ "${#plcrash_files[@]}" -eq 0 || "${#json_files[@]}" -eq 0 ]]; then
    return
  fi

  latest_plcrash="${plcrash_files[0]}"
  for candidate in "${plcrash_files[@]}"; do
    if [[ "$candidate" -nt "$latest_plcrash" ]]; then
      latest_plcrash="$candidate"
    fi
  done

  latest_json="${json_files[0]}"
  for candidate in "${json_files[@]}"; do
    if [[ "$candidate" -nt "$latest_json" ]]; then
      latest_json="$candidate"
    fi
  done
}

artifacts_are_fresh() {
  if [[ -z "$latest_plcrash" || -z "$latest_json" ]]; then
    return 1
  fi

  # Prefer filename change detection because filesystems can have coarse mtime granularity.
  if [[ -n "$baseline_plcrash" && -n "$baseline_json" ]]; then
    if [[ "$latest_plcrash" != "$baseline_plcrash" && "$latest_json" != "$baseline_json" ]]; then
      return 0
    fi
  fi

  [[ "$latest_plcrash" -nt "$MARKER_FILE" && "$latest_json" -nt "$MARKER_FILE" ]]
}

refresh_latest_artifacts
baseline_plcrash="$latest_plcrash"
baseline_json="$latest_json"
refresh_latest_unclean_artifact
baseline_unclean_json="$latest_unclean_json"

echo "▶ Prewarming TransactionClassifier build cache..."
set +e
prewarm_swiftpm_build
prewarm_status=$?
set -e
if [[ "$prewarm_status" -eq 124 ]]; then
  echo "❌ prewarm build timed out after ${PREWARM_BUILD_TIMEOUT_SECONDS}s."
  echo "---- prewarm output ----"
  awk '{print}' "$PREWARM_LOG"
  echo "------------------------"
  exit 1
elif [[ "$prewarm_status" -ne 0 ]]; then
  echo "❌ prewarm build failed before crash verification."
  echo "---- prewarm output ----"
  awk '{print}' "$PREWARM_LOG"
  echo "------------------------"
  exit 1
fi

echo "▶ Triggering intentional crash to seed pending crash report..."
#R010: Require intentional crash run to fail non-zero.
set +e
run_with_timeout "$CRASH_LAUNCH_TIMEOUT_SECONDS" "macOS forced-crash launch" \
  bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
    "$MACOS_UI_SWIFT_LOCK_HELPER" \
    "$MACOS_UI_SWIFTPM_LOCK" \
    "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
    "17_verify_macos_crash_test:forced-crash" \
    sh -c "cd \"\$1\" && TELLER_MACOS_FORCE_CRASH_ON_LAUNCH=1 swift run TransactionClassifier >/dev/null 2>&1" _ "$MACOS_UI_DIR"
forced_crash_status=$?
set -e

if [[ "$forced_crash_status" -eq 0 ]]; then
  echo "❌ expected forced crash run to exit non-zero."
  exit 1
fi
if [[ "$forced_crash_status" -eq 124 ]]; then
  echo "❌ forced crash launch timed out after ${CRASH_LAUNCH_TIMEOUT_SECONDS}s."
  exit 1
fi

echo "▶ Relaunching app to process pending crash report..."
touch "$MARKER_FILE"
sleep 1
set +e
run_relaunch
relaunch_status=$?
set -e

if [[ "$relaunch_status" -ne 0 ]] &&
   grep -q "cannot be accessed" "$LAUNCH_LOG" &&
   grep -q ".build/checkouts/" "$LAUNCH_LOG"; then
  #R045: Retry once after stale-checkout recovery.
  echo "ℹ️  Detected stale SwiftPM checkout state; repairing and retrying relaunch once..."
  set +e
  recover_swiftpm_state
  recovery_status=$?
  set -e
  if [[ "$recovery_status" -ne 0 ]]; then
    echo "❌ failed to recover SwiftPM state before relaunch retry."
    echo "---- recovery output ----"
    awk '{print}' "$RECOVERY_LOG"
    echo "-------------------------"
    exit 1
  fi

  set +e
  run_relaunch
  relaunch_status=$?
  set -e
fi

if [[ "$relaunch_status" -eq 124 ]]; then
  echo "❌ relaunch timed out before crash persistence log was observed."
  echo "---- launch output ----"
  awk '{print}' "$LAUNCH_LOG"
  echo "-----------------------"
  exit 1
elif [[ "$relaunch_status" -ne 0 ]]; then
  echo "❌ relaunch run failed while processing pending crash report."
  echo "---- launch output ----"
  awk '{print}' "$LAUNCH_LOG"
  echo "-----------------------"
  exit 1
fi

#R015: Confirm relaunch persisted pending crash report.
if ! grep -q "CrashReporter: saved pending crash report to" "$LAUNCH_LOG"; then
  echo "❌ relaunch did not report pending crash persistence."
  echo "---- launch output ----"
  awk '{print}' "$LAUNCH_LOG"
  echo "-----------------------"
  exit 1
fi

#R020: Require newly written .plcrash and .json artifacts after marker timestamp.
refresh_latest_artifacts
if [[ -z "$latest_plcrash" || -z "$latest_json" ]]; then
  echo "❌ expected crash artifacts under ${CRASH_REPORT_DIR}."
  exit 1
fi

if ! artifacts_are_fresh; then
  echo "❌ latest crash artifacts are not newer than this verification run."
  exit 1
fi

#R065: Simulate prior unclean termination and require fallback marker persistence on relaunch.
echo "▶ Simulating unclean termination replay marker and relaunching..."
touch "$UNCLEAN_MARKER_TIMESTAMP_FILE"
sleep 1
cat > "${CRASH_REPORT_DIR}/${UNCLEAN_MARKER_FILE_NAME}" <<EOF
{
  "bundle_id": "TransactionClassifier",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pid": 99999
}
EOF
set +e
run_unclean_marker_relaunch
unclean_relaunch_status=$?
set -e
if [[ "$unclean_relaunch_status" -eq 124 ]]; then
  echo "❌ unclean-marker relaunch timed out before fallback marker log was observed."
  echo "---- unclean launch output ----"
  awk '{print}' "$UNCLEAN_LOG"
  echo "-------------------------------"
  exit 1
elif [[ "$unclean_relaunch_status" -ne 0 ]]; then
  echo "❌ unclean-marker relaunch failed before fallback marker log was observed."
  echo "---- unclean launch output ----"
  awk '{print}' "$UNCLEAN_LOG"
  echo "-------------------------------"
  exit 1
fi
if ! grep -q "CrashReporter: saved unclean termination marker to" "$UNCLEAN_LOG"; then
  echo "❌ unclean-marker relaunch did not report fallback marker persistence."
  echo "---- unclean launch output ----"
  awk '{print}' "$UNCLEAN_LOG"
  echo "-------------------------------"
  exit 1
fi
refresh_latest_unclean_artifact
if [[ -z "$latest_unclean_json" ]]; then
  echo "❌ expected unclean termination marker artifact under ${CRASH_REPORT_DIR}."
  exit 1
fi
if ! unclean_artifact_is_fresh; then
  echo "❌ latest unclean termination marker artifact is not newer than this verification run."
  exit 1
fi

#R035: Print clear success output with artifact paths.
echo "✅ PLCrashReporter verification passed."
echo "   - crash report: ${latest_plcrash}"
echo "   - metadata: ${latest_json}"
echo "   - unclean marker: ${latest_unclean_json}"
