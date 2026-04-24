#!/usr/bin/env zsh
#R001: Run in strict shell mode and fail fast.
set -euo pipefail
#R005: Resolve repository root from script location.
repo_root="${0:A:h}"
#R010: Forward all args to TransactionClassifier with package-path.
exec swift run --package-path "$repo_root/macos-ui" TransactionClassifier "$@"
