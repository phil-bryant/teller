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
#R035: Expose XCUITest runtime overrides for worker-specific configuration.
XCUITEST_PROJECT="${XCUITEST_PROJECT:-./macos-ui/TransactionClassifierUIAutomation.xcodeproj}"
XCUITEST_SCHEME="${XCUITEST_SCHEME:-TransactionClassifierUITestHost-CI}"
XCUITEST_DESTINATION="${XCUITEST_DESTINATION:-platform=macOS}"
XCUITEST_DERIVED_DATA_PATH="${XCUITEST_DERIVED_DATA_PATH:-./macos-ui/.derivedData-ui-tests}"
#R050: Crash-reporter verification remains a standalone lane (script 11).
#R040: Support selecting specific smoke-suite scenario steps by numeric indices.
XCUITEST_SCENARIOS=(
  "matchAndClassifyShellLoads"
  "searchFilter"
  "unclassifiedFilterAutoRefresh"
  "selectionShowsTransactionId"
  "nextUnclassifiedShortcut"
  "applyCategory"
  "undoRestoresUnclassified"
  "undoRestoresPriorCategory"
  "nextUnclassifiedScrollsIntoView"
  "helpMenuListsHotkeys"
  "connectTabManualSave"
  "connectTabHidesNextUnclassified"
)
XCUITEST_SMOKE_SUITE="TransactionClassifierUITests/TransactionClassifierUITests/testMacOSUISmokeSuite"

if [[ $# -gt 1 ]]; then
  echo "❌ Usage: $0 [scenario-selector]"
  echo "   Examples: $0 1 | $0 1,3,5 | $0 1-10"
  exit 1
fi

XCUITEST_SELECTOR_RAW="${1:-}"
XCUITEST_SELECTED_NUMBERS=""

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
  MACOS_UI_SWIFTPM_LOCK="./macos-ui/.swiftpm-run.lock"
  MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS="${MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS:-600}"
  with_macos_ui_swift_lock() {
    local lock_dir="${MACOS_UI_SWIFTPM_LOCK}.d"
    local start_ts
    start_ts="$(date +%s)"
    mkdir -p ./macos-ui
    while ! mkdir "$lock_dir" 2>/dev/null; do
      if [[ -f "${lock_dir}/pid" ]]; then
        local owner_pid=""
        owner_pid="$(<"${lock_dir}/pid")"
        if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
          rm -rf "$lock_dir"
          continue
        fi
      fi
      if (( $(date +%s) - start_ts >= MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS )); then
        echo "❌ Timed out waiting for macOS UI SwiftPM lock at ${lock_dir}." >&2
        return 1
      fi
      sleep 1
    done
    echo $$ > "${lock_dir}/pid"
    "$@"
    local status=$?
    rm -rf "$lock_dir"
    return $status
  }
  #R015: Support explicit snapshot record mode for baseline updates.
  if [[ "$SNAPSHOT_RECORD" == "true" ]]; then
    with_macos_ui_swift_lock env SNAPSHOT_RECORD=1 swift test --package-path ./macos-ui --filter ContentViewSnapshotTests
  else
    with_macos_ui_swift_lock swift test --package-path ./macos-ui --filter ContentViewSnapshotTests
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

  echo "▶ Running macOS XCUITest smoke suite..."
  mkdir -p "$XCUITEST_DERIVED_DATA_PATH"
  xattr -dr com.apple.quarantine "$XCUITEST_DERIVED_DATA_PATH" >/dev/null 2>&1 || true

  if [[ -n "$XCUITEST_SELECTED_NUMBERS" ]]; then
    echo "ℹ️  Selecting XCUITest scenarios by index: ${XCUITEST_SELECTOR_RAW}"
    XCUITEST_STEPS="$XCUITEST_SELECTED_NUMBERS" env \
      xcodebuild test \
      -project "$XCUITEST_PROJECT" \
      -scheme "$XCUITEST_SCHEME" \
      -destination "$XCUITEST_DESTINATION" \
      -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
      -only-testing:"${XCUITEST_SMOKE_SUITE}"
  else
    xcodebuild test \
      -project "$XCUITEST_PROJECT" \
      -scheme "$XCUITEST_SCHEME" \
      -destination "$XCUITEST_DESTINATION" \
      -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
      -only-testing:"${XCUITEST_SMOKE_SUITE}"
  fi
else
  #R025: Support snapshot-only gate by explicitly skipping XCUITest lane.
  echo "ℹ️  Skipping XCUITest smoke suite (RUN_XCUITESTS=false)."
fi
