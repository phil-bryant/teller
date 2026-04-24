#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUN_SNAPSHOT_TESTS="${RUN_SNAPSHOT_TESTS:-true}"
RUN_XCUITESTS="${RUN_XCUITESTS:-true}"
SNAPSHOT_RECORD="${SNAPSHOT_RECORD:-false}"
XCUITEST_PROJECT="${XCUITEST_PROJECT:-./macos-ui/TransactionClassifierUIAutomation.xcodeproj}"
XCUITEST_SCHEME="${XCUITEST_SCHEME:-TransactionClassifierUITestHost}"
XCUITEST_DESTINATION="${XCUITEST_DESTINATION:-platform=macOS}"
XCUITEST_DERIVED_DATA_PATH="${XCUITEST_DERIVED_DATA_PATH:-./macos-ui/.derivedData-ui-tests}"

if [[ "$RUN_SNAPSHOT_TESTS" == "true" ]]; then
  echo "▶ Running macOS UI snapshot regression tests..."
  if [[ "$SNAPSHOT_RECORD" == "true" ]]; then
    SNAPSHOT_RECORD=1 swift test --package-path ./macos-ui --filter ContentViewSnapshotTests
  else
    swift test --package-path ./macos-ui --filter ContentViewSnapshotTests
  fi
else
  echo "ℹ️  Skipping snapshot regression tests (RUN_SNAPSHOT_TESTS=false)."
fi

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
  xcodebuild test \
    -project "$XCUITEST_PROJECT" \
    -scheme "$XCUITEST_SCHEME" \
    -destination "$XCUITEST_DESTINATION" \
    -derivedDataPath "$XCUITEST_DERIVED_DATA_PATH" \
    -only-testing:TransactionClassifierUITests
else
  echo "ℹ️  Skipping XCUITest smoke suite (RUN_XCUITESTS=false)."
fi
