#!/usr/bin/env zsh
#R001: Run in strict shell mode and fail fast.
set -euo pipefail
#R005: Resolve repository root from script location.
repo_root="${0:A:h}"
# Connect now runs in-process inside macos-ui (no localhost token server).
connect_api_url="inprocess://connect"
connect_manager_url="${TELLER_CONNECT_MANAGER_URL:-$connect_api_url}"
#R010: Forward all args to TransactionClassifier with package-path.
TELLER_CONNECT_API_URL="${connect_api_url}" \
TELLER_CONNECT_MANAGER_URL="${connect_manager_url}" \
exec swift run --package-path "$repo_root/macos-ui" TransactionClassifier "$@"
