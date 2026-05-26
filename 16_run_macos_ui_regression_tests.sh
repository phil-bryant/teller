#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Resolve script directory and run from repository root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
#R050: Crash-reporter verification remains a standalone lane (script 11).
#R040: Support selecting specific smoke-suite scenario steps by numeric indices.
XCUITEST_SCENARIOS=(
  "matchAndClassifyShellLoads"
  "searchFilter"
  "unclassifiedFilterAutoRefresh"
  #R055: Cover match-state picker behavior in XCUITest smoke suite.
  "matchStatePicker"
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
  "nextUnclassifiedScrollsIntoView"
  #R070: Verify long-list manual row selection does not auto-recenter scroll.
  "longListManualSelectionDoesNotRecenter"
  "helpMenuListsHotkeys"
  "connectTabLoadsConnections"
  "connectDeleteCancel"
  "connectDeleteConfirm"
  "connectAddAndEditButtons"
  "connectTabHidesNextUnclassified"
  #R065: Verify Connect tab hides Undo control.
  "connectTabHidesUndo"
  "manageCategoriesLoadAndToolbar"
  #R060: Verify Manage Categories tab hides Next Unclassified control.
  "manageCategoriesHidesNextUnclassified"
  "manageCategoryEditAndSave"
  "manageCategoryDelete"
)
XCUITEST_SMOKE_SUITE="TransactionClassifierUITests/TransactionClassifierUITests/testMacOSUISmokeSuite"

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

run_with_timeout() {
  local timeout_seconds="$1"
  local timeout_label="$2"
  shift 2
  if ! command -v "$TIMEOUT_HELPER_PYTHON" >/dev/null 2>&1; then
    echo "❌ ${TIMEOUT_HELPER_PYTHON} is required to enforce timeout for ${timeout_label}."
    return 1
  fi
  set +e
  "$TIMEOUT_HELPER_PYTHON" - "$timeout_seconds" "$timeout_label" "$TIMEOUT_HEARTBEAT_SECONDS" "$@" <<'PY'
import os
import signal
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
timeout_label = sys.argv[2]
heartbeat_seconds = int(sys.argv[3])
command = sys.argv[4:]
if timeout_seconds <= 0:
    timeout_seconds = 1
if heartbeat_seconds < 0:
    heartbeat_seconds = 0

proc = subprocess.Popen(command, preexec_fn=os.setsid)
start = time.monotonic()
next_heartbeat_at = heartbeat_seconds
while True:
    elapsed = int(time.monotonic() - start)
    if elapsed >= timeout_seconds:
      os.killpg(proc.pid, signal.SIGTERM)
      try:
          proc.wait(timeout=5)
      except subprocess.TimeoutExpired:
          os.killpg(proc.pid, signal.SIGKILL)
          proc.wait()
      raise SystemExit(124)
    try:
      proc.wait(timeout=1)
      raise SystemExit(proc.returncode)
    except subprocess.TimeoutExpired:
      if heartbeat_seconds > 0 and elapsed >= next_heartbeat_at:
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
  run_with_timeout "$SNAPSHOT_TIMEOUT_SECONDS" "macOS UI snapshot regression tests" \
    bash -c 'source "$1"; shift; macos_ui_with_swiftpm_lock "$@"' -- \
      "$MACOS_UI_SWIFT_LOCK_HELPER" \
      "$MACOS_UI_SWIFTPM_LOCK" \
      "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" \
      "16_run_macos_ui_regression_tests:snapshot" \
      "${snapshot_cmd[@]}"
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

  if [[ -n "$XCUITEST_SELECTED_NUMBERS" ]]; then
    echo "ℹ️  Selecting XCUITest scenarios by index: ${XCUITEST_SELECTOR_RAW}"
    export XCUITEST_STEPS="$XCUITEST_SELECTED_NUMBERS"
    run_with_timeout "$XCUITEST_TIMEOUT_SECONDS" "macOS XCUITest smoke suite" \
      xcodebuild test \
        -project "$XCUITEST_PROJECT" \
        -scheme "$XCUITEST_SCHEME" \
        -destination "$XCUITEST_DESTINATION" \
        -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
        -resultBundlePath "$XCUITEST_RESULT_BUNDLE_PATH" \
        -only-testing:"${XCUITEST_SMOKE_SUITE}"
  else
    run_with_timeout "$XCUITEST_TIMEOUT_SECONDS" "macOS XCUITest smoke suite" \
      xcodebuild test \
        -project "$XCUITEST_PROJECT" \
        -scheme "$XCUITEST_SCHEME" \
        -destination "$XCUITEST_DESTINATION" \
        -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
        -resultBundlePath "$XCUITEST_RESULT_BUNDLE_PATH" \
        -only-testing:"${XCUITEST_SMOKE_SUITE}"
  fi
else
  #R025: Support snapshot-only gate by explicitly skipping XCUITest lane.
  echo "ℹ️  Skipping XCUITest smoke suite (RUN_XCUITESTS=false)."
fi
