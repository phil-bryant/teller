#!/usr/bin/env bash
umask 007
#R001: Run property-based fuzz tests in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "$REPO_ROOT"
# shellcheck disable=SC1091
source "${REPO_ROOT}/src/scripts/export_test_cache_env.sh"
export_test_cache_env "$REPO_ROOT"
PYTHON_BIN="${REPO_ROOT}/teller-venv/bin/python3"
REPORT_DIR="${FUZZ_REPORT_DIR:-./artifacts/fuzz}"
#R030: Fuzz teller Python test targets with Hypothesis statistics enabled.
FUZZ_TEST_PATHS="${FUZZ_TEST_PATHS:-tests/py/properties}"
FUZZ_MAX_EXAMPLES="${FUZZ_MAX_EXAMPLES:-500}"
FUZZ_DEADLINE_MS="${FUZZ_DEADLINE_MS:-1000}"
FUZZ_TIMEOUT_SECONDS="${FUZZ_TIMEOUT_SECONDS:-300}"
FUZZ_MIN_PROPERTY_TESTS="${FUZZ_MIN_PROPERTY_TESTS:-4}"
FUZZ_MIN_TOTAL_EXAMPLES="${FUZZ_MIN_TOTAL_EXAMPLES:-}"
FUZZ_MIN_PER_TEST_RATIO_PERCENT="${FUZZ_MIN_PER_TEST_RATIO_PERCENT:-90}"
FUZZ_SUMMARY="${REPORT_DIR}/fuzz-summary.json"

if [[ "${REPORT_DIR}" != /* ]]; then
  REPORT_DIR="${REPO_ROOT}/${REPORT_DIR#./}"
fi
FUZZ_SUMMARY="${REPORT_DIR}/fuzz-summary.json"
mkdir -p "$REPORT_DIR"

print_runner_header() {
  local runner_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local runner_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Test Runner: ${runner_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${runner_url}"
  printf '%s\n' "$border"
}

#R025: Enforce a configurable fuzz lane timeout around pytest execution.
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  "$PYTHON_BIN" - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
command = sys.argv[2:]
if timeout_seconds <= 0:
    timeout_seconds = 1

proc = subprocess.Popen(command, preexec_fn=os.setsid)
try:
    proc.wait(timeout=timeout_seconds)
    raise SystemExit(proc.returncode)
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
    raise SystemExit(124)
PY
}

#R005: Fail fast when venv python or hypothesis is unavailable.
if [ ! -x "$PYTHON_BIN" ]; then
  echo "teller-venv python is required but was not found at ${PYTHON_BIN}."
  echo "Run ./02_create_venv.sh and ./04_load_requirements.sh first."
  exit 1
fi
if ! "$PYTHON_BIN" -c "import hypothesis" >/dev/null 2>&1; then
  echo "hypothesis is required in teller-venv but was not found."
  echo "Run ./04_load_requirements.sh to install test dependencies."
  exit 1
fi

if [ -z "$FUZZ_MIN_TOTAL_EXAMPLES" ]; then
  FUZZ_MIN_TOTAL_EXAMPLES=$((FUZZ_MIN_PROPERTY_TESTS * FUZZ_MAX_EXAMPLES * FUZZ_MIN_PER_TEST_RATIO_PERCENT / 100))
fi

#R010: Run configured property tests with bounded example counts and capture statistics.
#R020: Gate on pytest failures and minimum total passing examples (fuzz budget).
print_runner_header \
  "Hypothesis" \
  "Property-based fuzz lane for teller Python tests." \
  "Gates on pytest failures and minimum total passing examples." \
  "https://hypothesis.readthedocs.io/"

echo ""
echo "▶ Running property-based fuzz tests (${FUZZ_TEST_PATHS})"
echo "  max_examples=${FUZZ_MAX_EXAMPLES} deadline_ms=${FUZZ_DEADLINE_MS} min_total_examples=${FUZZ_MIN_TOTAL_EXAMPLES} min_per_test_ratio=${FUZZ_MIN_PER_TEST_RATIO_PERCENT}%"
echo "  hypothesis_storage_directory=${HYPOTHESIS_STORAGE_DIRECTORY}"
FUZZ_OUTPUT="$(mktemp)"
FUZZ_STARTED_AT_EPOCH="$(date +%s)"
set +e
run_with_timeout "$FUZZ_TIMEOUT_SECONDS" \
  env PYTHONPATH="$REPO_ROOT/src:$REPO_ROOT" \
    HYPOTHESIS_MAX_EXAMPLES="$FUZZ_MAX_EXAMPLES" \
    HYPOTHESIS_DEADLINE="$FUZZ_DEADLINE_MS" \
    HYPOTHESIS_STORAGE_DIRECTORY="$HYPOTHESIS_STORAGE_DIRECTORY" \
    "$PYTHON_BIN" -m pytest -p hypothesis "$FUZZ_TEST_PATHS" -q --hypothesis-show-statistics \
    > "$FUZZ_OUTPUT" 2>&1
FUZZ_EXIT=$?
set -e
FUZZ_FINISHED_AT_EPOCH="$(date +%s)"
FUZZ_ELAPSED_SECONDS=$((FUZZ_FINISHED_AT_EPOCH - FUZZ_STARTED_AT_EPOCH))
cat "$FUZZ_OUTPUT"
cp "$FUZZ_OUTPUT" "${REPORT_DIR}/fuzz-last.log"

if [ "$FUZZ_EXIT" -eq 124 ]; then
  echo "❌ FAIL: Property-based fuzz tests timed out after ${FUZZ_TIMEOUT_SECONDS}s."
  exit 1
fi

SUMMARY_EXIT=0
set +e
"$PYTHON_BIN" - "$FUZZ_OUTPUT" "$FUZZ_SUMMARY" "$FUZZ_EXIT" "$FUZZ_MIN_PROPERTY_TESTS" "$FUZZ_MIN_TOTAL_EXAMPLES" "$FUZZ_MAX_EXAMPLES" "$FUZZ_DEADLINE_MS" "$FUZZ_ELAPSED_SECONDS" "$FUZZ_TEST_PATHS" "$HYPOTHESIS_STORAGE_DIRECTORY" "$FUZZ_MIN_PER_TEST_RATIO_PERCENT" <<'PY'
import json
import math
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
pytest_exit = int(sys.argv[3])
min_property_tests = int(sys.argv[4])
min_total_examples = int(sys.argv[5])
max_examples = int(sys.argv[6])
deadline_ms = int(sys.argv[7])
elapsed_seconds = int(sys.argv[8])
test_paths = sys.argv[9]
hypothesis_storage_dir = sys.argv[10]
min_per_test_ratio = int(sys.argv[11])
log_text = log_path.read_text(encoding="utf-8", errors="replace")

hypothesis_stats_split = log_text.split("Hypothesis Statistics", 1)
hypothesis_stats = hypothesis_stats_split[1] if len(hypothesis_stats_split) > 1 else ""
block_pattern = re.compile(
    r"(?ms)^\s*(?P<nodeid>[^\n:]+(?:::[^\n:]+)+):\n"
    r"(?P<body>.*?)(?=^\s*[^\n:]+(?:::[^\n:]+)+:\n|\Z)"
)
property_tests = []
per_test_stats = {}
for match in block_pattern.finditer(hypothesis_stats):
    nodeid = match.group("nodeid").strip()
    body = match.group("body")
    if nodeid not in property_tests:
        property_tests.append(nodeid)
    passing_match = re.search(r"(\d+)\s+passing examples", body)
    failing_match = re.search(r"(\d+)\s+failing examples", body)
    invalid_match = re.search(r"(\d+)\s+invalid examples", body)
    passing = int(passing_match.group(1)) if passing_match else 0
    failing = int(failing_match.group(1)) if failing_match else 0
    invalid = int(invalid_match.group(1)) if invalid_match else 0
    per_test_stats[nodeid] = {
        "nodeid": nodeid,
        "passing_examples": passing,
        "failing_examples": failing,
        "invalid_examples": invalid,
    }

passing_examples = [item["passing_examples"] for item in per_test_stats.values()]
failing_examples = [item["failing_examples"] for item in per_test_stats.values()]
invalid_examples = [item["invalid_examples"] for item in per_test_stats.values()]
pytest_failed = pytest_exit != 0
total_passing = sum(passing_examples)
total_failing = sum(failing_examples)
total_invalid = sum(invalid_examples)
property_test_count = len(property_tests)
budget_failed = property_test_count < min_property_tests or total_passing < min_total_examples
gate_failed = pytest_failed or budget_failed
expected_min_passing_per_test = max(1, math.floor(max_examples * (min_per_test_ratio / 100.0)))
underfilled_property_tests = sorted(
    [
        nodeid
        for nodeid, stat in per_test_stats.items()
        if stat["passing_examples"] < expected_min_passing_per_test
    ]
)
invalid_ratio = 0.0 if total_passing == 0 else round(total_invalid / float(total_passing), 6)
transition_event_matches = re.findall(r"transition_edge:[A-Za-z0-9_:\->]+", log_text)
transition_event_counts = {}
for event_name in transition_event_matches:
    transition_event_counts[event_name] = transition_event_counts.get(event_name, 0) + 1
failure_seed_matches = re.findall(r"--hypothesis-seed=([0-9]+)", log_text)
failure_seed = failure_seed_matches[0] if failure_seed_matches else None
summary = {
    "fuzz_test_paths": test_paths,
    "hypothesis_storage_directory": hypothesis_storage_dir,
    "elapsed_seconds": elapsed_seconds,
    "pytest_exit": pytest_exit,
    "property_tests": sorted(property_tests),
    "property_test_stats": per_test_stats,
    "property_test_count": property_test_count,
    "min_property_tests": min_property_tests,
    "total_passing_examples": total_passing,
    "total_failing_examples": total_failing,
    "total_invalid_examples": total_invalid,
    "invalid_to_passing_ratio": invalid_ratio,
    "expected_min_passing_per_test": expected_min_passing_per_test,
    "underfilled_property_tests": underfilled_property_tests,
    "min_total_examples": min_total_examples,
    "configured_max_examples_per_test": max_examples,
    "configured_deadline_ms": deadline_ms,
    "configured_min_per_test_ratio_percent": min_per_test_ratio,
    "effective_max_examples_per_test": min((min(passing_examples) if passing_examples else 0), max_examples),
    "stateful_transition_events": transition_event_counts,
    "stateful_transition_event_count": sum(transition_event_counts.values()),
    "stateful_unique_transition_edges": len(transition_event_counts),
    "failure_hypothesis_seed": failure_seed,
    "pytest_failed": pytest_failed,
    "budget_failed": budget_failed,
    "gate_failed": gate_failed,
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
seed_path = summary_path.parent / "fuzz-failure-seed.txt"
if failure_seed:
    seed_path.write_text(failure_seed + "\n", encoding="utf-8")
elif seed_path.exists():
    seed_path.unlink()

print(
    f"Fuzz summary: property_tests={property_test_count} "
    f"passing_examples={total_passing} failing_examples={total_failing} invalid_examples={total_invalid}"
)
if underfilled_property_tests:
    print(
        "⚠️  WARN: Underfilled property tests (passing examples below expected floor): "
        + ", ".join(underfilled_property_tests)
    )
if pytest_failed:
    print("❌ FAIL: Property-based fuzz tests reported pytest failures.")
if property_test_count < min_property_tests:
    print(
        f"❌ FAIL: Expected at least {min_property_tests} property tests, collected {property_test_count}."
    )
if total_passing < min_total_examples:
    print(
        f"❌ FAIL: Total passing examples {total_passing} is below budget {min_total_examples}."
    )
if property_test_count > 0 and underfilled_property_tests:
    print(
        "❌ FAIL: One or more property tests did not reach the minimum per-test passing example floor "
        f"({expected_min_passing_per_test})."
    )
    gate_failed = True
if gate_failed:
    raise SystemExit(1)
PY
SUMMARY_EXIT=$?
set -e

if [ "$SUMMARY_EXIT" -ne 0 ]; then
  if [ "$FUZZ_EXIT" -ne 0 ]; then
    cp "$FUZZ_OUTPUT" "${REPORT_DIR}/fuzz-failure-last.log"
    echo "Failure replay log: ${REPORT_DIR}/fuzz-failure-last.log"
  fi
  exit 1
fi
if [ "$FUZZ_EXIT" -ne 0 ]; then
  cp "$FUZZ_OUTPUT" "${REPORT_DIR}/fuzz-failure-last.log"
  echo "Failure replay log: ${REPORT_DIR}/fuzz-failure-last.log"
  echo "❌ FAIL: Property-based fuzz tests failed."
  exit 1
fi

#R015: Emit concise success output on completion.
echo "✅ PASS: Property-based fuzz tests completed (passing_examples>=${FUZZ_MIN_TOTAL_EXAMPLES}, property_tests>=${FUZZ_MIN_PROPERTY_TESTS})."
echo "Fuzz report: ${FUZZ_SUMMARY}"
echo "Hypothesis cache: ${HYPOTHESIS_STORAGE_DIRECTORY}"
