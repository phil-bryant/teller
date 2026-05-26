#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TELEMETRY_DIR="${QUALITY_TELEMETRY_DIR:-./artifacts/telemetry}"
TREND_PATH="${TELEMETRY_DIR}/quality-trend.json"
HISTORY_PATH="${TELEMETRY_DIR}/quality-history.ndjson"

if [[ ! -f "$TREND_PATH" ]]; then
  echo "❌ FAIL: missing trend file at ${TREND_PATH}" >&2
  echo "Run ./24_run_all_tests_parallel.sh first to generate telemetry." >&2
  exit 1
fi

python3 - "$TREND_PATH" "$HISTORY_PATH" <<'PY'
import json
import sys
from pathlib import Path

trend_path = Path(sys.argv[1])
history_path = Path(sys.argv[2])
trend = json.loads(trend_path.read_text(encoding="utf-8"))

history_count = 0
if history_path.exists():
    history_count = sum(1 for line in history_path.read_text(encoding="utf-8").splitlines() if line.strip())

rolling = trend.get("rolling_20_runs", {})
slo = trend.get("performance_slo", {})
rolling_14d = trend.get("rolling_14d", {})

print("Local quality trend report")
print(f"- latest run: {trend.get('latest_run_started_at', 'unknown')}")
print(f"- latest score: {trend.get('latest_score', 0.0):.3f} / 10.0")
print(f"- history entries: {history_count}")
print(f"- rolling20 score avg: {rolling.get('score_avg', 0.0):.3f}")
print(f"- rolling20 wall p50: {rolling.get('wall_p50_seconds', 0.0):.2f}s (target <= 130s)")
print(f"- rolling20 wall p95: {rolling.get('wall_p95_seconds', 0.0):.2f}s (target <= 150s)")
print(f"- rolling14d score avg: {rolling_14d.get('score_avg', 0.0):.3f}")
print(f"- rolling14d pass reliability: {rolling_14d.get('pass_reliability', 0.0):.2%}")

if slo.get("fail"):
    print("- status: FAIL (p95 exceeded hard threshold)")
elif slo.get("warn"):
    print("- status: WARN (p95 above target)")
else:
    print("- status: PASS")
PY
