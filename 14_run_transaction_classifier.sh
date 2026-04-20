#!/usr/bin/env zsh
set -euo pipefail
repo_root="${0:A:h}"
exec swift run --package-path "$repo_root/macos" TransactionClassifier "$@"
