#!/usr/bin/env bash
#R001: Enforce strict shell behavior for telemetry cleanup.
set -euo pipefail

#R005: Resolve repository root from script location for cwd-independent execution.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TELEMETRY_DIR="${QUALITY_TELEMETRY_DIR:-./artifacts/telemetry}"
KEEP_COUNT="${QUALITY_LANE_SUMMARY_KEEP:-20}"

#R010: Require a non-negative integer retention value.
if [[ ! "$KEEP_COUNT" =~ ^[0-9]+$ ]]; then
  echo "❌ FAIL: QUALITY_LANE_SUMMARY_KEEP must be a non-negative integer (got '${KEEP_COUNT}')." >&2
  exit 1
fi

if [[ ! -d "$TELEMETRY_DIR" ]]; then
  echo "ℹ️  Telemetry directory not found: ${TELEMETRY_DIR} (nothing to prune)."
  exit 0
fi

shopt -s nullglob
lane_summaries=( "${TELEMETRY_DIR}"/lane-summary-*.json )
shopt -u nullglob

if [[ "${#lane_summaries[@]}" -eq 0 ]]; then
  echo "ℹ️  No lane summary files found in ${TELEMETRY_DIR}."
  exit 0
fi

sorted_summaries=()
while IFS= read -r summary_file; do
  sorted_summaries+=("$summary_file")
done < <(printf '%s\n' "${lane_summaries[@]}" | sort)
total_count="${#sorted_summaries[@]}"

if [[ "$total_count" -le "$KEEP_COUNT" ]]; then
  echo "ℹ️  Nothing pruned: ${total_count} lane summary files present; keep=${KEEP_COUNT}."
  exit 0
fi

# Move pruned (superseded) telemetry summaries to ~/.Trash instead of deleting (no-rm policy).
safe_move_to_trash() {
  local path="$1" trash_dir=""
  [[ -e "$path" || -L "$path" ]] || return 0
  trash_dir="$(mktemp -d "${HOME}/.Trash/teller_quality_telemetry_XXXXXX")"
  mv "$path" "${trash_dir}/$(basename "$path")"
}

delete_count=$((total_count - KEEP_COUNT))
for ((idx = 0; idx < delete_count; idx++)); do
  safe_move_to_trash "${sorted_summaries[$idx]}"
done

echo "✅ Pruned lane summary artifacts: removed=${delete_count}, kept=${KEEP_COUNT}, total_before=${total_count}."
