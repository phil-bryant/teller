#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Resolve script directory and run from repository root.
SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "$REPO_ROOT"

RUN_SNAPSHOT_TESTS="${RUN_SNAPSHOT_TESTS:-true}"
RUN_XCUITESTS="${RUN_XCUITESTS:-true}"
#R030: Default to full UI regression coverage when no overrides are provided.
SNAPSHOT_RECORD="${SNAPSHOT_RECORD:-false}"
MACOS_UI_SWIFTPM_LOCK="${MACOS_UI_SWIFTPM_LOCK:-./src/macos-ui/.swiftpm-run.lock}"
MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS="${MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS:-600}"
SNAPSHOT_TIMEOUT_SECONDS="${SNAPSHOT_TIMEOUT_SECONDS:-900}"
XCUITEST_TIMEOUT_SECONDS="${XCUITEST_TIMEOUT_SECONDS:-180}"
TIMEOUT_HELPER_PYTHON="${TIMEOUT_HELPER_PYTHON:-python3}"
TIMEOUT_HEARTBEAT_SECONDS="${TIMEOUT_HEARTBEAT_SECONDS:-15}"
#R035: Expose XCUITest runtime overrides for worker-specific configuration.
XCUITEST_PROJECT="${XCUITEST_PROJECT:-./src/macos-ui/TransactionClassifierUIAutomation.xcodeproj}"
XCUITEST_SCHEME="${XCUITEST_SCHEME:-TransactionClassifierUITestHost-CI}"
XCUITEST_DESTINATION="${XCUITEST_DESTINATION:-platform=macOS}"
XCUITEST_DERIVED_DATA_PATH="${XCUITEST_DERIVED_DATA_PATH:-./src/macos-ui/.derivedData-ui-tests}"
XCUITEST_RESULT_BUNDLE_PATH="${XCUITEST_RESULT_BUNDLE_PATH:-./artifacts/macos-ui-regression/xcuitest-results.xcresult}"
XCUITEST_PROFILE="${XCUITEST_PROFILE:-smoke}"
XCUITEST_SUCCESS_GRACE_SECONDS="${XCUITEST_SUCCESS_GRACE_SECONDS:-1}"
#R050: Crash-reporter verification remains a standalone lane (script 11).
#R040: Support selecting specific smoke-suite scenario steps by numeric indices.
XCUITEST_SCENARIOS=(
  "matchAndClassifyShellLoads"
  "searchFilter"
  "unclassifiedFilterAutoRefresh"
  "onlyUnmovedToggle"
  "refreshButton"
  "selectionShowsTransactionId"
  "nextUnclassifiedShortcut"
  "loadMoreButton"
  "applyCategory"
  "clearSelection"
  "undoRestoresUnclassified"
  "undoRestoresPriorCategory"
  "candidatesAndEmailPane"
  "emailSearch"
  "matchActions"
  "confirmPreservesEmailRendering"
  "nextUnclassifiedScrollsIntoView"
  #R070: Verify long-list manual row selection does not auto-recenter scroll.
  "longListManualSelectionDoesNotRecenter"
  "helpMenuListsHotkeys"
  "connectTabLoadsConnections"
  "connectDeleteCancel"
  "connectDeleteConfirm"
  #R080: Ensure Connect Add/Edit smoke path asserts in-sheet ESC hint copy.
  "connectAddAndEditButtons"
  "connectTabHidesNextUnclassified"
  #R065: Verify Connect tab hides Undo control.
  "connectTabHidesUndo"
  "manageCategoriesLoadAndToolbar"
  #R060: Verify Manage Categories tab hides Next Unclassified control.
  "manageCategoriesHidesNextUnclassified"
  "manageCategoryEditAndSave"
  "manageCategoryDelete"
  #R055: Extended all-values match-state sweep for deep coverage.
  "matchStatePickerAllValuesExtended"
  #R075: Exercise advanced transaction scalar filters in smoke coverage.
  "advancedTransactionFilter"
  #R075: Exercise advanced email body/received-date filters in smoke coverage.
  "advancedEmailSearch"
)
XCUITEST_SMOKE_SUITE="TransactionClassifierUITests/TransactionClassifierUITests/testMacOSUISmokeSuite"
XCUITEST_SMOKE_DEFAULT_STEPS="${XCUITEST_SMOKE_DEFAULT_STEPS:-1-32}"
XCUITEST_EXTENDED_DEFAULT_STEPS="${XCUITEST_EXTENDED_DEFAULT_STEPS:-1-32}"

if [[ $# -gt 1 ]]; then
  echo "❌ Usage: $0 [scenario-selector]"
  echo "   Examples: $0 1 | $0 1,3,5 | $0 1-10"
  exit 1
fi

XCUITEST_SELECTOR_RAW="${1:-}"
XCUITEST_SELECTED_NUMBERS=""

MACOS_UI_SWIFT_LOCK_HELPER="./src/scripts/macos_ui_swift_lock.sh"
if [[ ! -f "$MACOS_UI_SWIFT_LOCK_HELPER" ]]; then
  echo "❌ macOS UI SwiftPM lock helper not found at ${MACOS_UI_SWIFT_LOCK_HELPER}."
  exit 1
fi
# shellcheck disable=SC1090
source "$MACOS_UI_SWIFT_LOCK_HELPER"

swiftpm_state_looks_stale() {
  local output_text="$1"
  [[ "$output_text" == *"cannot be accessed"* && "$output_text" == *".build/"* ]] && return 0
  [[ "$output_text" == *"was compiled with module cache path"* ]] && return 0
  [[ "$output_text" == *"is defined in both"* && "$output_text" == *"ModuleCache"* ]] && return 0
  return 1
}

clear_conflicting_swiftpm_build_dirs() {
  local output_text="$1"
  local cache_roots=""
  cache_roots="$(
    python3 - <<'PY' "$output_text"
import re
import sys

text = sys.argv[1]
roots = sorted(set(re.findall(r"(/[^'\s]+/src/macos-ui)/\.build", text)))
for root in roots:
    print(root)
PY
  )"
  if [[ -n "$cache_roots" ]]; then
    while IFS= read -r cache_root; do
      [[ -n "$cache_root" ]] || continue
      if [[ -d "$cache_root/.build" ]]; then
        rm -rf "$cache_root/.build"
      fi
    done <<< "$cache_roots"
  fi
  rm -rf ./src/macos-ui/.build
}

run_with_timeout() {
  #R085: Timeout guard is watchdog-only; do not introduce fixed sleeps to pace interactions.
  local timeout_seconds="$1"
  local timeout_label="$2"
  shift 2
  if ! command -v "$TIMEOUT_HELPER_PYTHON" >/dev/null 2>&1; then
    echo "❌ ${TIMEOUT_HELPER_PYTHON} is required to enforce timeout for ${timeout_label}."
    return 1
  fi
  set +e
  "$TIMEOUT_HELPER_PYTHON" - "$timeout_seconds" "$timeout_label" "$TIMEOUT_HEARTBEAT_SECONDS" "$@" <<'PY'
import fcntl
import os
import select
import signal
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
timeout_label = sys.argv[2]
heartbeat_seconds = int(sys.argv[3])
command = sys.argv[4:]
success_grace_seconds = int(os.environ.get("TIMEOUT_SUCCESS_GRACE_SECONDS", "0") or "0")
if timeout_seconds <= 0:
    timeout_seconds = 1
if heartbeat_seconds < 0:
    heartbeat_seconds = 0
if success_grace_seconds < 0:
    success_grace_seconds = 0

proc = subprocess.Popen(
    command,
    preexec_fn=os.setsid,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=False,
    bufsize=0,
)
stdout_fd = proc.stdout.fileno()
stdout_flags = fcntl.fcntl(stdout_fd, fcntl.F_GETFL)
fcntl.fcntl(stdout_fd, fcntl.F_SETFL, stdout_flags | os.O_NONBLOCK)
start = time.monotonic()
next_heartbeat_at = heartbeat_seconds
marker_seen_at = None
failed_markers_seen = False
line_buffer = ""

def note_line(line: str) -> None:
    global marker_seen_at, failed_markers_seen
    if not line:
        return
    if " failed at " in line or " with 1 failure" in line or ": error:" in line:
        failed_markers_seen = True
    if "** TEST SUCCEEDED **" in line and not failed_markers_seen:
        marker_seen_at = marker_seen_at or time.monotonic()

def terminate_process() -> None:
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()

while True:
    now = time.monotonic()
    elapsed = int(now - start)
    if elapsed >= timeout_seconds:
        terminate_process()
        raise SystemExit(124)

    if marker_seen_at is not None and success_grace_seconds > 0 and (now - marker_seen_at) >= success_grace_seconds:
        terminate_process()
        print(
            f"ℹ️  {timeout_label} reported success; stopping lingering xcodebuild after {success_grace_seconds}s grace.",
            flush=True,
        )
        raise SystemExit(0 if not failed_markers_seen else 1)

    readable, _, _ = select.select([proc.stdout], [], [], 1)
    if readable:
        try:
            chunk = os.read(stdout_fd, 4096)
        except BlockingIOError:
            chunk = b""
        if not chunk:
            if line_buffer:
                note_line(line_buffer)
                sys.stdout.write(line_buffer + "\n")
                sys.stdout.flush()
                line_buffer = ""
            if proc.poll() is not None:
                raise SystemExit(1 if failed_markers_seen else proc.returncode)
        else:
            text = chunk.decode("utf-8", errors="replace")
            sys.stdout.write(text)
            sys.stdout.flush()
            line_buffer += text
            while "\n" in line_buffer:
                line, line_buffer = line_buffer.split("\n", 1)
                note_line(line)
    elif proc.poll() is not None:
        if line_buffer:
            note_line(line_buffer)
        raise SystemExit(1 if failed_markers_seen else proc.returncode)

    if heartbeat_seconds > 0 and marker_seen_at is None and elapsed >= next_heartbeat_at:
        print(f"⏳ Still running {timeout_label} ({elapsed}s elapsed)...", flush=True)
        next_heartbeat_at += heartbeat_seconds
PY
  local status=$?
  set -e
  if [[ "$status" -eq 124 ]]; then
    echo "❌ Timed out after ${timeout_seconds}s while running ${timeout_label}."
  fi
  return "$status"
}

if [[ -n "$XCUITEST_SELECTOR_RAW" ]]; then
  total_scenarios="${#XCUITEST_SCENARIOS[@]}"
  IFS=',' read -r -a selector_tokens <<<"$XCUITEST_SELECTOR_RAW"
  for token in "${selector_tokens[@]}"; do
    token="${token//[[:space:]]/}"
    if [[ -z "$token" ]]; then
      echo "❌ Empty selector token in '$XCUITEST_SELECTOR_RAW'."
      exit 1
    fi

    if [[ "$token" =~ ^[0-9]+$ ]]; then
      start="$token"
      end="$token"
    elif [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if (( start > end )); then
        echo "❌ Invalid range '$token' (start > end)."
        exit 1
      fi
    else
      echo "❌ Invalid selector token '$token'. Expected N or N-M."
      exit 1
    fi

    for (( index=start; index<=end; index++ )); do
      #R045: Fail fast when a selector references a non-existent scenario number.
      if (( index < 1 || index > total_scenarios )); then
        echo "❌ Unknown UI regression scenario number '$index'. Valid range is 1-$total_scenarios."
        exit 1
      fi

      if [[ ",$XCUITEST_SELECTED_NUMBERS," != *",$index,"* ]]; then
        if [[ -z "$XCUITEST_SELECTED_NUMBERS" ]]; then
          XCUITEST_SELECTED_NUMBERS="$index"
        else
          XCUITEST_SELECTED_NUMBERS="${XCUITEST_SELECTED_NUMBERS},${index}"
        fi
      fi
    done
  done
fi

if [[ -z "$XCUITEST_SELECTOR_RAW" ]]; then
  case "$XCUITEST_PROFILE" in
    smoke)
      XCUITEST_SELECTOR_RAW="$XCUITEST_SMOKE_DEFAULT_STEPS"
      XCUITEST_SELECTED_NUMBERS="$XCUITEST_SMOKE_DEFAULT_STEPS"
      ;;
    extended|full)
      XCUITEST_SELECTOR_RAW="$XCUITEST_EXTENDED_DEFAULT_STEPS"
      XCUITEST_SELECTED_NUMBERS="$XCUITEST_EXTENDED_DEFAULT_STEPS"
      ;;
    *)
      echo "❌ Invalid XCUITEST_PROFILE '$XCUITEST_PROFILE'. Use smoke, extended, or full."
      exit 1
      ;;
  esac
fi

#R010: Run snapshot regression lane when enabled.
if [[ "$RUN_SNAPSHOT_TESTS" == "true" ]]; then
  echo "▶ Running macOS UI snapshot regression tests..."
  if ! command -v swift >/dev/null 2>&1; then
    echo "❌ swift is required for macOS UI snapshot regression tests."
    exit 1
  fi
  #R015: Support explicit snapshot record mode for baseline updates.
  snapshot_cmd=(swift test --package-path ./src/macos-ui --filter ContentViewSnapshotTests)
  if [[ "$SNAPSHOT_RECORD" == "true" ]]; then
    snapshot_cmd=(env SNAPSHOT_RECORD=1 swift test --package-path ./src/macos-ui --filter ContentViewSnapshotTests)
  fi
  set +e
  snapshot_output="$(
    run_with_timeout "$SNAPSHOT_TIMEOUT_SECONDS" "macOS UI snapshot regression tests" \
      bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
        "$MACOS_UI_SWIFT_LOCK_HELPER" \
        "$MACOS_UI_SWIFTPM_LOCK" \
        "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
        "16_run_macos_ui_regression_tests:snapshot" \
        "${snapshot_cmd[@]}"
  )"
  snapshot_status=$?
  set -e
  printf '%s\n' "$snapshot_output"
  if [[ "$snapshot_status" -ne 0 ]] && swiftpm_state_looks_stale "$snapshot_output"; then
    echo "ℹ️  Detected stale SwiftPM cache state; clearing ./src/macos-ui/.build and retrying snapshot lane once..."
    clear_conflicting_swiftpm_build_dirs "$snapshot_output"
    set +e
    snapshot_output="$(
      run_with_timeout "$SNAPSHOT_TIMEOUT_SECONDS" "macOS UI snapshot regression tests" \
        bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
          "$MACOS_UI_SWIFT_LOCK_HELPER" \
          "$MACOS_UI_SWIFTPM_LOCK" \
          "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
          "16_run_macos_ui_regression_tests:snapshot" \
          "${snapshot_cmd[@]}"
    )"
    snapshot_status=$?
    set -e
    printf '%s\n' "$snapshot_output"
  fi
  if [[ "$snapshot_status" -ne 0 ]]; then
    exit "$snapshot_status"
  fi
else
  echo "ℹ️  Skipping snapshot regression tests (RUN_SNAPSHOT_TESTS=false)."
fi

#R020: Run XCUITest smoke suite when enabled and required tools exist.
if [[ "$RUN_XCUITESTS" == "true" ]]; then
  if [[ ! -d "$XCUITEST_PROJECT" ]]; then
    echo "❌ XCUITest project not found at $XCUITEST_PROJECT"
    exit 1
  fi
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ xcodebuild is required for macOS UI smoke tests."
    exit 1
  fi
  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    echo "❌ Xcode first-launch tasks are incomplete (xcodebuild -checkFirstLaunchStatus failed)."
    exit 1
  fi
  if ! xcodebuild -license check >/dev/null 2>&1; then
    echo "❌ Xcode license is not accepted (xcodebuild -license check failed)."
    exit 1
  fi

  echo "▶ Running macOS XCUITest smoke suite..."
  mkdir -p "$XCUITEST_DERIVED_DATA_PATH"
  mkdir -p "$(dirname "$XCUITEST_RESULT_BUNDLE_PATH")"
  rm -rf "$XCUITEST_RESULT_BUNDLE_PATH"
  xattr -dr com.apple.quarantine "$XCUITEST_DERIVED_DATA_PATH" >/dev/null 2>&1 || true

  XCUITEST_STEPS_FILE="$REPO_ROOT/artifacts/macos-ui-regression/xcuitest-steps.env"
  mkdir -p "$(dirname "$XCUITEST_STEPS_FILE")"
  printf '%s' "${XCUITEST_SELECTED_NUMBERS:-$XCUITEST_SMOKE_DEFAULT_STEPS}" > "$XCUITEST_STEPS_FILE"
  export XCUITEST_STEPS_FILE

  if [[ -n "$XCUITEST_SELECTED_NUMBERS" ]]; then
    echo "ℹ️  Using XCUITest profile '${XCUITEST_PROFILE}' with scenarios: ${XCUITEST_SELECTOR_RAW}"
    export XCUITEST_STEPS="$XCUITEST_SELECTED_NUMBERS"
    TIMEOUT_SUCCESS_GRACE_SECONDS="$XCUITEST_SUCCESS_GRACE_SECONDS" \
      run_with_timeout "$XCUITEST_TIMEOUT_SECONDS" "macOS XCUITest smoke suite" \
      xcodebuild test \
        -project "$XCUITEST_PROJECT" \
        -scheme "$XCUITEST_SCHEME" \
        -destination "$XCUITEST_DESTINATION" \
        -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
        -resultBundlePath "$XCUITEST_RESULT_BUNDLE_PATH" \
        -parallel-testing-enabled NO \
        -maximum-concurrent-test-device-destinations 1 \
        -only-testing:"${XCUITEST_SMOKE_SUITE}"
  else
    TIMEOUT_SUCCESS_GRACE_SECONDS="$XCUITEST_SUCCESS_GRACE_SECONDS" \
      run_with_timeout "$XCUITEST_TIMEOUT_SECONDS" "macOS XCUITest smoke suite" \
      xcodebuild test \
        -project "$XCUITEST_PROJECT" \
        -scheme "$XCUITEST_SCHEME" \
        -destination "$XCUITEST_DESTINATION" \
        -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
        -resultBundlePath "$XCUITEST_RESULT_BUNDLE_PATH" \
        -parallel-testing-enabled NO \
        -maximum-concurrent-test-device-destinations 1 \
        -only-testing:"${XCUITEST_SMOKE_SUITE}"
  fi
else
  #R025: Support snapshot-only gate by explicitly skipping XCUITest lane.
  echo "ℹ️  Skipping XCUITest smoke suite (RUN_XCUITESTS=false)."
fi
