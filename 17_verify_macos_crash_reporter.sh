#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Execute from repository root regardless of caller directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MACOS_UI_DIR="${MACOS_UI_DIR:-./macos-ui}"
CRASH_REPORT_DIR="${CRASH_REPORT_DIR:-${HOME}/Library/Application Support/TransactionClassifier/CrashReports}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-2}"
LAUNCH_LOG="$(mktemp)"
MARKER_FILE="$(mktemp)"
latest_plcrash=""
latest_json=""
baseline_plcrash=""
baseline_json=""

#R030: Fail clearly when required local tooling is unavailable.
if ! command -v swift >/dev/null 2>&1; then
  echo "❌ swift is required for PLCrashReporter verification."
  exit 1
fi

if [[ ! -d "$MACOS_UI_DIR" ]]; then
  echo "❌ macOS UI package path not found at ${MACOS_UI_DIR}."
  exit 1
fi

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

echo "▶ Triggering intentional crash to seed pending crash report..."
#R010: Require intentional crash run to fail non-zero.
if (cd "$MACOS_UI_DIR" && TELLER_MACOS_FORCE_CRASH_ON_LAUNCH=1 swift run TransactionClassifier >/dev/null 2>&1); then
  echo "❌ expected forced crash run to exit non-zero."
  exit 1
fi

echo "▶ Relaunching app to process pending crash report..."
touch "$MARKER_FILE"
sleep 1
(cd "$MACOS_UI_DIR" && swift run TransactionClassifier >"$LAUNCH_LOG" 2>&1) &
APP_PID=$!
FOUND_SAVE_LOG="false"
FOUND_FRESH_ARTIFACTS="false"

#R015: Confirm relaunch processes pending crash via log signal or fresh artifacts.
for ((second=1; second<=STARTUP_WAIT_SECONDS; second++)); do
  if [[ -f "$LAUNCH_LOG" ]] && grep -q "CrashReporter: saved pending crash report to" "$LAUNCH_LOG"; then
    FOUND_SAVE_LOG="true"
  fi
  refresh_latest_artifacts
  if artifacts_are_fresh; then
    FOUND_FRESH_ARTIFACTS="true"
    break
  fi
  if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    :
  fi
  # Allow crash artifact persistence to complete even after process exit.
  sleep 1
done

if kill -0 "$APP_PID" >/dev/null 2>&1; then
  kill "$APP_PID" >/dev/null 2>&1 || true
  wait "$APP_PID" >/dev/null 2>&1 || true
else
  wait "$APP_PID" >/dev/null 2>&1 || true
fi
pkill -x "TransactionClassifier" >/dev/null 2>&1 || true

if [[ "$FOUND_SAVE_LOG" != "true" && "$FOUND_FRESH_ARTIFACTS" != "true" ]]; then
  echo "ℹ️  Did not observe persistence log line; validating via artifact timestamps instead."
fi

#R020: Require newly written .plcrash and .json artifacts after marker timestamp.
refresh_latest_artifacts
if [[ -z "$latest_plcrash" || -z "$latest_json" ]]; then
  echo "❌ expected crash artifacts under ${CRASH_REPORT_DIR}."
  exit 1
fi

if ! artifacts_are_fresh; then
  echo "❌ latest crash artifacts are not newer than this verification run."
  echo "---- launch output ----"
  cat "$LAUNCH_LOG"
  echo "-----------------------"
  exit 1
fi

#R035: Print clear success output with artifact paths.
echo "✅ PLCrashReporter verification passed."
echo "   - crash report: ${latest_plcrash}"
echo "   - metadata: ${latest_json}"
