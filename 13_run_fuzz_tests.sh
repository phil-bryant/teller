#!/usr/bin/env bash
umask 007
#R001: Run property-based fuzz tests in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
PYTHON_BIN="${REPO_ROOT}/teller-venv/bin/python3"
REPORT_DIR="${FUZZ_REPORT_DIR:-./artifacts/fuzz}"
#R030: Fuzz teller Python test targets with Hypothesis statistics enabled.
FUZZ_TEST_PATHS="${FUZZ_TEST_PATHS:-tests/py}"
FUZZ_MAX_EXAMPLES="${FUZZ_MAX_EXAMPLES:-500}"
FUZZ_DEADLINE_MS="${FUZZ_DEADLINE_MS:-1000}"
FUZZ_TIMEOUT_SECONDS="${FUZZ_TIMEOUT_SECONDS:-300}"
FUZZ_MIN_PROPERTY_TESTS="${FUZZ_MIN_PROPERTY_TESTS:-0}"
FUZZ_MIN_TOTAL_EXAMPLES="${FUZZ_MIN_TOTAL_EXAMPLES:-}"
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
  echo "Run ./02_create_venv.sh and ./03_load_requirements.sh first."
  exit 1
fi
if ! "$PYTHON_BIN" -c "import hypothesis" >/dev/null 2>&1; then
  echo "hypothesis is required in teller-venv but was not found."
  echo "Run ./03_load_requirements.sh to install test dependencies."
  exit 1
fi

if [ -z "$FUZZ_MIN_TOTAL_EXAMPLES" ]; then
  FUZZ_MIN_TOTAL_EXAMPLES=$((FUZZ_MIN_PROPERTY_TESTS * FUZZ_MAX_EXAMPLES * 80 / 100))
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
echo "  max_examples=${FUZZ_MAX_EXAMPLES} deadline_ms=${FUZZ_DEADLINE_MS} min_total_examples=${FUZZ_MIN_TOTAL_EXAMPLES}"
FUZZ_OUTPUT="$(mktemp)"
set +e
run_with_timeout "$FUZZ_TIMEOUT_SECONDS" \
  env PYTHONPATH="$REPO_ROOT/src:$REPO_ROOT" \
    HYPOTHESIS_MAX_EXAMPLES="$FUZZ_MAX_EXAMPLES" \
    HYPOTHESIS_DEADLINE="$FUZZ_DEADLINE_MS" \
    "$PYTHON_BIN" -m pytest -p hypothesis "$FUZZ_TEST_PATHS" -q --hypothesis-show-statistics \
    > "$FUZZ_OUTPUT" 2>&1
FUZZ_EXIT=$?
set -e
cat "$FUZZ_OUTPUT"

if [ "$FUZZ_EXIT" -eq 124 ]; then
  echo "❌ FAIL: Property-based fuzz tests timed out after ${FUZZ_TIMEOUT_SECONDS}s."
  exit 1
fi

SUMMARY_EXIT=0
"$PYTHON_BIN" - "$FUZZ_OUTPUT" "$FUZZ_SUMMARY" "$FUZZ_EXIT" "$FUZZ_MIN_PROPERTY_TESTS" "$FUZZ_MIN_TOTAL_EXAMPLES" "$FUZZ_MAX_EXAMPLES" "$FUZZ_DEADLINE_MS" <<'PY'
import json
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
log_text = log_path.read_text(encoding="utf-8", errors="replace")

property_tests = sorted(set(re.findall(r"::(test_[A-Za-z0-9_]+)", log_text)))
passing_examples = [int(value) for value in re.findall(r"(\d+) passing examples", log_text)]
failing_examples = [int(value) for value in re.findall(r"(\d+) failing examples", log_text)]
invalid_examples = [int(value) for value in re.findall(r"(\d+) invalid examples", log_text)]
pytest_failed = pytest_exit != 0
total_passing = sum(passing_examples)
total_failing = sum(failing_examples)
total_invalid = sum(invalid_examples)
property_test_count = len(property_tests)
budget_failed = property_test_count < min_property_tests or total_passing < min_total_examples
gate_failed = pytest_failed or budget_failed
summary = {
    "pytest_exit": pytest_exit,
    "property_tests": property_tests,
    "property_test_count": property_test_count,
    "min_property_tests": min_property_tests,
    "total_passing_examples": total_passing,
    "total_failing_examples": total_failing,
    "total_invalid_examples": total_invalid,
    "min_total_examples": min_total_examples,
    "max_examples_per_test": max_examples,
    "deadline_ms": deadline_ms,
    "pytest_failed": pytest_failed,
    "budget_failed": budget_failed,
    "gate_failed": gate_failed,
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

print(
    f"Fuzz summary: property_tests={property_test_count} "
    f"passing_examples={total_passing} failing_examples={total_failing} invalid_examples={total_invalid}"
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
if gate_failed:
    raise SystemExit(1)
PY
SUMMARY_EXIT=$?

if [ "$SUMMARY_EXIT" -ne 0 ]; then
  exit 1
fi
if [ "$FUZZ_EXIT" -ne 0 ]; then
  echo "❌ FAIL: Property-based fuzz tests failed."
  exit 1
fi

#R015: Emit concise success output on completion.
echo "✅ PASS: Property-based fuzz tests completed (passing_examples>=${FUZZ_MIN_TOTAL_EXAMPLES}, property_tests>=${FUZZ_MIN_PROPERTY_TESTS})."
echo "Fuzz report: ${FUZZ_SUMMARY}"
