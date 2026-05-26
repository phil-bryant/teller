#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R005: Execute from repository root regardless of caller directory.
cd "$SCRIPT_DIR"

# Keep runtime caches out of the repository root.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/src/scripts/export_test_cache_env.sh"
export_test_cache_env "$SCRIPT_DIR"

#R010: Discover numbered check scripts dynamically by basename from tests/.
SELF_SCRIPT_BASENAME="$(basename "${BASH_SOURCE[0]}")"
CHECKS_DIR="./tests"
CHECK_ORDER_FILE="${CHECKS_DIR}/new_tests_order.txt"
CHECKS=()
if [[ -f "$CHECK_ORDER_FILE" ]]; then
  while IFS= read -r script || [[ -n "$script" ]]; do
    [[ -n "$script" ]] || continue
    if [[ "$script" == "$SELF_SCRIPT_BASENAME" ]]; then
      continue
    fi
    if [[ "$script" =~ ^t?[0-9]{2}_.*$ && "$script" =~ (^|_)tests?(_|\.sh$) ]]; then
      CHECKS+=("$script")
    fi
  done < "$CHECK_ORDER_FILE"
else
  for candidate in "${CHECKS_DIR}"/*.sh; do
    script="$(basename "$candidate")"
    if [[ "$script" == "$SELF_SCRIPT_BASENAME" ]]; then
      continue
    fi
    if [[ "$script" =~ ^t?[0-9]{2}_.*$ && "$script" =~ (^|_)tests?(_|\.sh$) ]]; then
      CHECKS+=("$script")
    fi
  done
fi

if [[ "${#CHECKS[@]}" -eq 0 ]]; then
  echo "❌ FAIL: no numbered test scripts found (expected names containing test or tests)." >&2
  exit 1
fi

#R040: Remain a standalone meta-runner; child check scripts must not invoke this script.

#R035: Persist per-check stdout/stderr log artifacts.
REPORT_DIR="${PARALLEL_CHECKS_REPORT_DIR:-./artifacts/parallel}"
mkdir -p "$REPORT_DIR"
TELEMETRY_DIR="${QUALITY_TELEMETRY_DIR:-./artifacts/telemetry}"
mkdir -p "$TELEMETRY_DIR"
PROGRESS_INTERVAL_SECONDS="${PARALLEL_CHECKS_PROGRESS_INTERVAL_SECONDS:-1}"
if [[ ! "$PROGRESS_INTERVAL_SECONDS" =~ ^[0-9]+$ || "$PROGRESS_INTERVAL_SECONDS" -le 0 ]]; then
  PROGRESS_INTERVAL_SECONDS=1
fi
LOCK_FILE="${SCRIPT_DIR}/.10_run_all_tests_parallel.lock"
PROGRESS_INLINE=false
if [[ -t 1 ]]; then
  PROGRESS_INLINE=true
fi
child_pids=()
cleanup_finished=false
signal_exit_code=""

# Ensure trap cleanup can safely invoke this even before later function definitions.
finish_progress_line() {
  if [[ "$PROGRESS_INLINE" == "true" ]]; then
    printf '\n'
  fi
}

#R050: Prevent concurrent invocations of this orchestrator from the same repo root.
release_single_run_lock() {
  local current_lock_pid=""
  if [[ -f "$LOCK_FILE" ]]; then
    current_lock_pid="$(<"$LOCK_FILE")"
    if [[ "$current_lock_pid" == "$$" ]]; then
      rm -f "$LOCK_FILE"
    fi
  fi
}

acquire_single_run_lock() {
  local existing_lock_pid=""
  if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi
  if [[ -f "$LOCK_FILE" ]]; then
    existing_lock_pid="$(<"$LOCK_FILE")"
  fi
  if [[ -n "$existing_lock_pid" ]] && kill -0 "$existing_lock_pid" 2>/dev/null; then
    echo "❌ FAIL: another 10_run_all_tests_parallel.sh run is already active (pid ${existing_lock_pid})." >&2
    return 1
  fi
  rm -f "$LOCK_FILE"
  if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi
  echo "❌ FAIL: unable to acquire single-run lock at ${LOCK_FILE}" >&2
  return 1
}

#R055: Terminate launched child checks on interrupt or termination.
terminate_child_checks() {
  local pid child grandchild
  for pid in "${child_pids[@]}"; do
    [[ -n "$pid" ]] || continue
    kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
      kill -TERM "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null || true
      for grandchild in $(pgrep -P "$child" 2>/dev/null || true); do
        kill -TERM "$grandchild" 2>/dev/null || true
      done
    done
  done

  sleep 1

  for pid in "${child_pids[@]}"; do
    [[ -n "$pid" ]] || continue
    kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
      kill -KILL "-$child" 2>/dev/null || kill -KILL "$child" 2>/dev/null || true
      for grandchild in $(pgrep -P "$child" 2>/dev/null || true); do
        kill -KILL "$grandchild" 2>/dev/null || true
      done
    done
  done
}

stop_on_signal() {
  local exit_code="$1"
  if [[ "$cleanup_finished" == "true" ]]; then
    exit "$exit_code"
  fi
  cleanup_finished=true
  terminate_child_checks
  finish_progress_line
  echo "Interrupted; stopped parallel checks." >&2
  release_single_run_lock
  exit "$exit_code"
}

check_for_signal() {
  if [[ -n "$signal_exit_code" ]]; then
    stop_on_signal "$signal_exit_code"
  fi
}

trap 'if [[ "$cleanup_finished" != "true" ]]; then cleanup_finished=true; finish_progress_line; release_single_run_lock; fi' EXIT
trap 'signal_exit_code=130' INT
trap 'signal_exit_code=143' TERM
acquire_single_run_lock

render_progress() {
  local completed="$1"
  local total="$2"
  local bar_width=20
  local percent=0
  local filled=0
  local empty=0
  local filled_bar=""
  local empty_bar=""

  if [[ "$total" -gt 0 ]]; then
    percent=$((completed * 100 / total))
    filled=$((completed * bar_width / total))
  fi
  empty=$((bar_width - filled))
  filled_bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  empty_bar="$(printf '%*s' "$empty" '' | tr ' ' '-')"
  if [[ "$PROGRESS_INLINE" == "true" ]]; then
    printf '\r\033[2KProgress: [%s/%s (%s%%)] [%s%s]' "$completed" "$total" "$percent" "$filled_bar" "$empty_bar"
  else
    echo "Progress: [${completed}/${total} (${percent}%)] [${filled_bar}${empty_bar}]"
  fi
}

emit_result_line() {
  local message="$1"
  if [[ "$PROGRESS_INLINE" == "true" ]]; then
    # Clear the inline progress row before printing a completion line.
    printf '\r\033[2K'
  fi
  echo "$message"
}

derive_failure_reason() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    echo "missing-log"
    return
  fi
  if grep -q "Timed out waiting for macOS UI SwiftPM lock" "$log_file"; then
    echo "lock-timeout"
    return
  fi
  if grep -q "Timed out after .* while running" "$log_file"; then
    echo "lane-timeout"
    return
  fi
  if grep -q "^❌" "$log_file"; then
    echo "script-error"
    return
  fi
  echo "nonzero-exit"
}

print_failure_excerpt() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    return
  fi
  emit_result_line "   ↳ recent log lines:"
  awk 'NF { lines[count % 3] = $0; count++ } END { start = (count > 3 ? count - 3 : 0); for (i = start; i < count; i++) { idx = i % 3; print "     " lines[idx]; } }' "$log_file"
}

for script in "${CHECKS[@]}"; do
  if [[ ! -f "${CHECKS_DIR}/${script}" ]]; then
    echo "❌ FAIL: expected check script not found: ${CHECKS_DIR}/${script}" >&2
    exit 1
  fi
done

echo "▶ Starting parallel checks (${#CHECKS[@]} scripts)..."

#R060: Record orchestrator wall-clock start for long-pole timing.
run_start_epoch="$(date +%s)"
long_pole_script=""
long_pole_seconds=0

#R015: Launch all check scripts concurrently.
#R020: Capture each child exit code independently.
for script in "${CHECKS[@]}"; do
  script_path="${CHECKS_DIR}/${script}"
  log="${REPORT_DIR}/${script%.sh}.log"
  rm -f "${log}" "${log}.exit" "${log}.exit.reported" "${log}.start"
  date +%s > "${log}.start"
  (
    set +e
    # Keep lanes parallel while isolating shared resources.
    lane_api_url="${PARALLEL_CLASSIFIER_API_URL:-http://127.0.0.1:${PARALLEL_CLASSIFIER_API_PORT:-8787}}"
    lane_dast_base_port="${PARALLEL_DAST_BASE_PORT:-8788}"
    lane_dast_reuse_api="${PARALLEL_DAST_REUSE_EXISTING_API:-false}"
    lane_dast_db_profile="${PARALLEL_DAST_DB_PROFILE:-${TELLER_DB_PROFILE:-}}"
    crash_check_delay="${PARALLEL_CRASH_CHECK_DELAY_SECONDS:-0}"
    if [[ "$script" == "t15_verify_macos_crash_test.sh" && "$crash_check_delay" =~ ^[0-9]+$ && "$crash_check_delay" -gt 0 ]]; then
      sleep "$crash_check_delay"
    fi
    if [[ "$script" == "t05_deploy_database_verification_test.sh" || "$script" == "t06_run_sql_unit_tests.sh" || "$script" == "t16_classification_persistence_verification_test.sh" || "$script" == "t12_run_dynamic_security_tests.sh" ]]; then
      if [[ "$script" == "t16_classification_persistence_verification_test.sh" ]]; then
        TELLER_DB_HOST="${TELLER_DB_HOST:-127.0.0.1}" \
        TELLER_DB_SSLMODE="${TELLER_DB_SSLMODE:-require}" \
        TELLER_CLASSIFIER_API_URL="${TELLER_CLASSIFIER_API_URL:-${lane_api_url}}" \
          "${script_path}" >"${log}" 2>&1
      elif [[ "$script" == "t12_run_dynamic_security_tests.sh" ]]; then
        TELLER_DB_HOST="${TELLER_DB_HOST:-127.0.0.1}" \
        TELLER_DB_SSLMODE="${TELLER_DB_SSLMODE:-require}" \
        DAST_BASE_PORT="${DAST_BASE_PORT:-${lane_dast_base_port}}" \
        DAST_REUSE_EXISTING_API="${DAST_REUSE_EXISTING_API:-${lane_dast_reuse_api}}" \
        TELLER_DB_PROFILE="${lane_dast_db_profile}" \
          "${script_path}" >"${log}" 2>&1
      else
        TELLER_DB_HOST="${TELLER_DB_HOST:-127.0.0.1}" \
        TELLER_DB_SSLMODE="${TELLER_DB_SSLMODE:-require}" \
          "${script_path}" >"${log}" 2>&1
      fi
    else
      "${script_path}" >"${log}" 2>&1
    fi
    exit_code=$?
    echo "$exit_code" > "${log}.exit"
  ) &
  child_pids+=("$!")
done

if [[ "${PARALLEL_CHECKS_TEST_INTERRUPT:-}" == "1" ]]; then
  stop_on_signal 130
fi

#R025: Print each pass/fail line as soon as its check completes (completion order).
pass_count=0
fail_count=0
total="${#CHECKS[@]}"
reported=0

#R045: Emit continuous aggregate progress while checks are still running.
render_progress "$reported" "$total"
while [[ "$reported" -lt "$total" ]]; do
  check_for_signal
  for script in "${CHECKS[@]}"; do
    exit_file="${REPORT_DIR}/${script%.sh}.log.exit"
    reported_file="${exit_file}.reported"
    if [[ ! -f "$exit_file" || -f "$reported_file" ]]; then
      continue
    fi
    : >"$reported_file"
    reported=$((reported + 1))
    log="${REPORT_DIR}/${script%.sh}.log"
    start_file="${log}.start"
    start_epoch=0
    if [[ -f "$start_file" ]]; then
      start_epoch="$(<"$start_file")"
    fi
    elapsed=0
    if [[ "$start_epoch" -gt 0 ]]; then
      elapsed=$(( $(date +%s) - start_epoch ))
    fi
    completed_exit="$(<"$exit_file")"
    if [[ "$elapsed" -gt "$long_pole_seconds" ]]; then
      long_pole_seconds="$elapsed"
      long_pole_script="$script"
    fi
    if [[ "$completed_exit" -eq 0 ]]; then
      emit_result_line "✅ PASS: ${script} (${elapsed}s)"
      pass_count=$((pass_count + 1))
    else
      failure_reason="$(derive_failure_reason "$log")"
      emit_result_line "❌ FAIL: ${script} (exit ${completed_exit}, ${elapsed}s, reason=${failure_reason}) — see ${log}"
      print_failure_excerpt "$log"
      fail_count=$((fail_count + 1))
    fi
  done
  check_for_signal
  render_progress "$reported" "$total"
  if [[ "$reported" -lt "$total" ]]; then
    sleep "$PROGRESS_INTERVAL_SECONDS"
  fi
done

set +e
for pid in "${child_pids[@]}"; do
  wait "$pid"
done
set -e

#R060: Report wall time and longest lane before overall gate.
wall_elapsed=$(( $(date +%s) - run_start_epoch ))
echo "Timing: wall ${wall_elapsed}s; long pole ${long_pole_script} (${long_pole_seconds}s)"

python3 - "$REPORT_DIR" "$TELEMETRY_DIR" "$run_start_epoch" "$wall_elapsed" "$total" "$pass_count" "$fail_count" <<'PY'
import json
import math
import os
import statistics
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

report_dir = Path(sys.argv[1])
telemetry_dir = Path(sys.argv[2])
run_started_epoch = int(sys.argv[3])
wall_elapsed = int(sys.argv[4])
total = int(sys.argv[5])
passed = int(sys.argv[6])
failed = int(sys.argv[7])
run_started_at = datetime.fromtimestamp(run_started_epoch, tz=timezone.utc)

history_path = telemetry_dir / "quality-history.ndjson"
trend_path = telemetry_dir / "quality-trend.json"
lane_summary_path = telemetry_dir / f"lane-summary-{run_started_at.strftime('%Y%m%dT%H%M%SZ')}.json"

lane_entries = []
for exit_file in sorted(report_dir.glob("*.log.exit")):
    log_file = exit_file.with_suffix("")
    lane_name = exit_file.name.replace(".log.exit", "")
    start_file = Path(str(log_file) + ".start")
    start_epoch = run_started_epoch
    if start_file.exists():
        try:
            start_epoch = int(start_file.read_text(encoding="utf-8").strip())
        except ValueError:
            start_epoch = run_started_epoch
    end_epoch = int(exit_file.stat().st_mtime)
    elapsed = max(0, end_epoch - start_epoch)
    try:
        exit_code = int(exit_file.read_text(encoding="utf-8").strip())
    except ValueError:
        exit_code = 99
    lane_entries.append(
        {
            "lane": lane_name,
            "status": "pass" if exit_code == 0 else "fail",
            "exit_code": exit_code,
            "elapsed_seconds": elapsed,
        }
    )

lane_status = {entry["lane"]: 1.0 if entry["status"] == "pass" else 0.0 for entry in lane_entries}

def score_group(prefixes):
    values = [lane_status[name] for name in lane_status if any(name.startswith(prefix) for prefix in prefixes)]
    if not values:
        return 1.0
    return sum(values) / len(values)

lane_reliability = (passed / total) if total else 0.0
behavioral_coverage = score_group(("10_", "11_", "13_", "15_", "16_", "19_", "20_", "22_"))
effectiveness_quality = score_group(("12_", "14_"))
security_runtime_quality = score_group(("06_", "07_", "23_"))
overall_score = round(
    (
        (0.35 * lane_reliability)
        + (0.25 * behavioral_coverage)
        + (0.20 * effectiveness_quality)
        + (0.20 * security_runtime_quality)
    )
    * 10.0,
    3,
)

run_payload = {
    "run_started_at": run_started_at.isoformat(),
    "wall_elapsed_seconds": wall_elapsed,
    "total_lanes": total,
    "passed_lanes": passed,
    "failed_lanes": failed,
    "score": overall_score,
    "components": {
        "lane_reliability": round(lane_reliability, 4),
        "behavioral_coverage": round(behavioral_coverage, 4),
        "effectiveness_quality": round(effectiveness_quality, 4),
        "security_runtime_quality": round(security_runtime_quality, 4),
    },
    "lanes": lane_entries,
}

lane_summary_path.write_text(json.dumps(run_payload, indent=2), encoding="utf-8")
with history_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(run_payload, separators=(",", ":")) + "\n")

history_rows = []
for line in history_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        history_rows.append(json.loads(line))
    except json.JSONDecodeError:
        continue

last_20 = history_rows[-20:]
wall_samples = [row.get("wall_elapsed_seconds", 0) for row in last_20]
score_samples = [row.get("score", 0.0) for row in last_20]
now = datetime.now(tz=timezone.utc)
recent_14d = []
for row in history_rows:
    stamp = row.get("run_started_at")
    try:
        parsed = datetime.fromisoformat(stamp)
    except Exception:
        continue
    if parsed >= now - timedelta(days=14):
        recent_14d.append(row)

def percentile(values, p):
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = (len(ordered) - 1) * p
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return float(ordered[lower])
    weight = rank - lower
    return float(ordered[lower] + (ordered[upper] - ordered[lower]) * weight)

p50 = percentile(wall_samples, 0.50)
p95 = percentile(wall_samples, 0.95)
warn = p95 > 150.0 and len(wall_samples) >= 3
fail_gate = p95 > 160.0 and len(wall_samples) >= 3

trend_payload = {
    "latest_run_started_at": run_payload["run_started_at"],
    "latest_score": overall_score,
    "rolling_21_runs": {
        "count": len(last_20),
        "score_avg": round(sum(score_samples) / len(score_samples), 3) if score_samples else 0.0,
        "wall_p50_seconds": round(p50, 2),
        "wall_p95_seconds": round(p95, 2),
    },
    "rolling_14d": {
        "count": len(recent_14d),
        "score_avg": round(sum(row.get("score", 0.0) for row in recent_14d) / len(recent_14d), 3) if recent_14d else 0.0,
        "pass_reliability": round(
            sum((row.get("passed_lanes", 0) / row.get("total_lanes", 1)) for row in recent_14d) / len(recent_14d),
            4,
        ) if recent_14d else 0.0,
    },
    "performance_slo": {
        "target_p50_seconds": 130,
        "target_p95_seconds": 150,
        "warn": warn,
        "fail": fail_gate,
    },
}
trend_path.write_text(json.dumps(trend_payload, indent=2), encoding="utf-8")
PY
echo "Quality telemetry: ${TELEMETRY_DIR}/quality-history.ndjson"
echo "Quality trend: ${TELEMETRY_DIR}/quality-trend.json"

#R030: Print overall pass/fail gate and exit code.
if [[ "$fail_count" -eq 0 ]]; then
  echo "✅ PASS: all parallel checks succeeded (${pass_count}/${total})"
  exit 0
fi

echo "❌ FAIL: parallel checks: ${pass_count}/${total} passed"
exit 1
