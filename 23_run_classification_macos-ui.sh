#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail
#R005: Resolve repository root from script location.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_path="$repo_root/src/macos-ui"
binary="$package_path/.build/debug/TransactionClassifier"
# Connect now runs in-process inside macos-ui (no localhost token server).
connect_api_url="inprocess://connect"
connect_manager_url="${TELLER_CONNECT_MANAGER_URL:-$connect_api_url}"
#R010: Forward all args to TransactionClassifier with package-path.
# Build synchronously so failures stop the script; launch the GUI detached from the TTY so
# keystrokes typed while using the app are not echoed into this terminal session.
if ! TELLER_CONNECT_API_URL="${connect_api_url}" \
     TELLER_CONNECT_MANAGER_URL="${connect_manager_url}" \
     swift build --package-path "$package_path" -c debug --product TransactionClassifier; then
  exit 1
fi
TELLER_CONNECT_API_URL="${connect_api_url}" \
TELLER_CONNECT_MANAGER_URL="${connect_manager_url}" \
"$binary" "$@" &
exit 0
