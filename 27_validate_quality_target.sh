#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TELEMETRY_DIR="${QUALITY_TELEMETRY_DIR:-./artifacts/telemetry}"
HISTORY_PATH="${TELEMETRY_DIR}/quality-history.ndjson"
TARGET_SCORE="${QUALITY_TARGET_SCORE:-9.5}"
TARGET_RELIABILITY="${QUALITY_TARGET_RELIABILITY:-0.95}"

if [[ ! -f "$HISTORY_PATH" ]]; then
  echo "❌ FAIL: missing quality history at ${HISTORY_PATH}" >&2
  echo "Run ./25_run_all_tests_parallel.sh over time to build history." >&2
  exit 1
fi

python3 - "$HISTORY_PATH" "$TARGET_SCORE" "$TARGET_RELIABILITY" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

history_path = Path(sys.argv[1])
target_score = float(sys.argv[2])
target_reliability = float(sys.argv[3])
now = datetime.now(timezone.utc)

rows = []
for line in history_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not isinstance(payload, dict):
        continue
    stamp = payload.get("run_started_at")
    if not isinstance(stamp, str):
        continue
    try:
        ts = datetime.fromisoformat(stamp)
    except ValueError:
        continue
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    rows.append((ts, payload))

recent = [(ts, payload) for ts, payload in rows if ts >= now - timedelta(days=21)]
if len(recent) < 2:
    print("❌ FAIL: insufficient history to validate two consecutive weeks.")
    print(f"- recent runs found: {len(recent)} (need at least 2 across 14+ days)")
    raise SystemExit(1)

recent.sort(key=lambda item: item[0])
span_days = (recent[-1][0] - recent[0][0]).days
if span_days < 7:
    print("❌ FAIL: run history does not yet span two weeks.")
    print(f"- observed span: {span_days} day(s) (need at least 7)")
    raise SystemExit(1)

qualified = []
for ts, payload in recent:
    score = float(payload.get("score", 0.0))
    reliability = float((payload.get("components") or {}).get("lane_reliability", 0.0))
    if score >= target_score and reliability >= target_reliability:
        iso_year, iso_week, _ = ts.isocalendar()
        qualified.append((iso_year, iso_week, score, reliability, ts))

if not qualified:
    print("❌ FAIL: no runs met the quality target.")
    raise SystemExit(1)

week_keys = sorted({(year, week) for year, week, *_ in qualified})
has_consecutive = False
for idx in range(1, len(week_keys)):
    prev_year, prev_week = week_keys[idx - 1]
    year, week = week_keys[idx]
    if year == prev_year and week == prev_week + 1:
        has_consecutive = True
        break
    if year == prev_year + 1 and prev_week >= 52 and week == 1:
        has_consecutive = True
        break

if not has_consecutive:
    print("❌ FAIL: target met, but not across consecutive ISO weeks yet.")
    print(f"- qualifying weeks: {week_keys}")
    raise SystemExit(1)

latest_ts, latest_payload = recent[-1]
print("✅ PASS: quality target validated for two consecutive weeks.")
print(f"- latest run: {latest_ts.isoformat()}")
print(f"- latest score: {float(latest_payload.get('score', 0.0)):.3f}")
print(f"- target score: {target_score:.3f}")
print(f"- target reliability: {target_reliability:.2%}")
PY
