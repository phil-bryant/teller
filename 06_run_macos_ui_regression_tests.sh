#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Resolve script directory and run from repository root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUN_SNAPSHOT_TESTS="${RUN_SNAPSHOT_TESTS:-true}"
RUN_XCUITESTS="${RUN_XCUITESTS:-true}"
RUN_CRASH_REPORTER_SMOKE_TEST="${RUN_CRASH_REPORTER_SMOKE_TEST:-false}"
#R030: Default to full UI regression coverage when no overrides are provided.
SNAPSHOT_RECORD="${SNAPSHOT_RECORD:-false}"
#R035: Expose XCUITest runtime overrides for worker-specific configuration.
XCUITEST_PROJECT="${XCUITEST_PROJECT:-./macos-ui/TransactionClassifierUIAutomation.xcodeproj}"
XCUITEST_SCHEME="${XCUITEST_SCHEME:-TransactionClassifierUITestHost-CI}"
XCUITEST_DESTINATION="${XCUITEST_DESTINATION:-platform=macOS}"
XCUITEST_DERIVED_DATA_PATH="${XCUITEST_DERIVED_DATA_PATH:-./macos-ui/.derivedData-ui-tests}"
#R040: Support selecting specific XCUITests by numeric indices.
XCUITEST_METHODS=(
  "testSearchFilterFindsFixtureRow"
  "testNextUnclassifiedShortcutUpdatesDetailSelection"
  "testApplyCategoryFromTypeaheadUpdatesSelection"
  "testUndoShortcutRestoresClassification"
  "testUndoRestoresPriorCategoryOnAlreadyClassifiedRow"
  "testLoadMoreAppendsRowsAndUpdatesStatusText"
  "testInitialUnclassifiedToggleIsOnByDefault"
  "testTogglingUnclassifiedAutomaticallyRefreshesList"
  "testNextUnclassifiedScrollsTargetIntoView"
  "testDetailHeaderShowsTransactionIdentifier"
  "testConnectTabManualSaveFlow"
  "testConnectTabDoesNotExposeNextUnclassifiedToolbarControl"
  "testHelpMenuListsAllHotkeys"
)

if [[ $# -gt 1 ]]; then
  echo "❌ Usage: $0 [test-selector]"
  echo "   Examples: $0 1 | $0 1,3,5 | $0 1-10"
  exit 1
fi

XCUITEST_SELECTOR_RAW="${1:-}"
XCUITEST_SELECTED_NUMBERS=""

if [[ -n "$XCUITEST_SELECTOR_RAW" ]]; then
  total_tests="${#XCUITEST_METHODS[@]}"
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
      #R045: Fail fast when a selector references a non-existent test number.
      if (( index < 1 || index > total_tests )); then
        echo "❌ Unknown UI regression test number '$index'. Valid range is 1-$total_tests."
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
  #R015: Support explicit snapshot record mode for baseline updates.
  if [[ "$SNAPSHOT_RECORD" == "true" ]]; then
    SNAPSHOT_RECORD=1 swift test --package-path ./macos-ui --filter ContentViewSnapshotTests
  else
    swift test --package-path ./macos-ui --filter ContentViewSnapshotTests
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
  XCUITEST_ONLY_TESTING_ARGS=()
  if [[ -z "$XCUITEST_SELECTED_NUMBERS" ]]; then
    XCUITEST_ONLY_TESTING_ARGS+=("-only-testing:TransactionClassifierUITests")
  else
    echo "ℹ️  Selecting XCUITests by index: ${XCUITEST_SELECTOR_RAW}"
    IFS=',' read -r -a selected_numbers <<<"$XCUITEST_SELECTED_NUMBERS"
    for index in "${selected_numbers[@]}"; do
      method="${XCUITEST_METHODS[$((index - 1))]}"
      XCUITEST_ONLY_TESTING_ARGS+=(
        "-only-testing:TransactionClassifierUITests/TransactionClassifierUITests/${method}"
      )
    done
  fi
  xcodebuild test \
    -project "$XCUITEST_PROJECT" \
    -scheme "$XCUITEST_SCHEME" \
    -destination "$XCUITEST_DESTINATION" \
    -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
    "${XCUITEST_ONLY_TESTING_ARGS[@]}"
else
  #R025: Support snapshot-only gate by explicitly skipping XCUITest lane.
  echo "ℹ️  Skipping XCUITest smoke suite (RUN_XCUITESTS=false)."
fi

#R050: Optionally run PLCrashReporter startup smoke verification in UI regression lane.
if [[ "$RUN_CRASH_REPORTER_SMOKE_TEST" == "true" ]]; then
  echo "▶ Running PLCrashReporter smoke verification..."
  ./17_verify_macos_crash_reporter.sh
else
  echo "ℹ️  Skipping PLCrashReporter smoke verification (RUN_CRASH_REPORTER_SMOKE_TEST=false)."
fi
