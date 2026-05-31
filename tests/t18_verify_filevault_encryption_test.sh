#!/usr/bin/env bash
umask 007
#R001: Run in strict shell mode and execute from repository root.
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "$REPO_ROOT"

FILEVAULT_STATUS_CMD="${FILEVAULT_STATUS_CMD:-fdesetup status}"

#R010: Require macOS for FileVault verification.
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ FileVault verification requires macOS."
  exit 1
fi

#R015: Require a FileVault status command before enforcement.
if [[ "$FILEVAULT_STATUS_CMD" == "fdesetup status" ]] && ! command -v fdesetup >/dev/null 2>&1; then
  echo "❌ fdesetup is required for FileVault verification."
  exit 1
fi

echo "▶ Checking FileVault encryption status..."
set +e
filevault_status="$($FILEVAULT_STATUS_CMD 2>&1)"
filevault_exit=$?
set -e

if [[ "$filevault_exit" -ne 0 ]]; then
  echo "❌ Failed to read FileVault status: ${filevault_status}"
  exit 1
fi

#R005: Pass only when FileVault is enabled; fail when off or unknown.
if [[ "$filevault_status" == *"FileVault is On."* ]]; then
  echo "✅ FileVault encryption is enabled."
  exit 0
fi

echo "❌ FileVault encryption is not enabled."
echo "   Status: ${filevault_status}"
exit 1
