#!/usr/bin/env bash
# Deprecated: use ./24_run_classification_macos-ui.sh
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "▶ 23_run_classification_macos-ui.sh is deprecated; use ./24_run_classification_macos-ui.sh" >&2
exec "${script_dir}/24_run_classification_macos-ui.sh" "$@"
