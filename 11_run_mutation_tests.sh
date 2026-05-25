#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
REPO_ROOT="$SCRIPT_DIR"

REPORT_DIR="${MUTATION_REPORT_DIR:-./.security-reports}"
MUTATION_SCORE_THRESHOLD="${MUTATION_SCORE_THRESHOLD:-90}"
MUTATOR_COVERAGE_THRESHOLD="${MUTATOR_COVERAGE_THRESHOLD:-70}"
MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-600}"
#R025: Record optional file exclusions in the persisted mutation summary.
MUTATION_EXCLUDE_FILES="${MUTATION_EXCLUDE_FILES:-}"
PYTHON_BIN="${REPO_ROOT}/teller-venv/bin/python3"
PYTEST_DIR="${REPO_ROOT}/tests/py"
MUTMUT_CICD_STATS="${REPO_ROOT}/mutants/mutmut-cicd-stats.json"
MUTATION_SUMMARY="${REPORT_DIR}/mutation-summary.json"

if [[ "${REPORT_DIR}" != /* ]]; then
  REPORT_DIR="${REPO_ROOT}/${REPORT_DIR#./}"
fi
MUTATION_SUMMARY="${REPORT_DIR}/mutation-summary.json"

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

#R005: Fail fast when required commands are unavailable.
if [ ! -x "$PYTHON_BIN" ]; then
  echo "teller-venv python is required but was not found at ${PYTHON_BIN}."
  echo "Run ./02_create_venv.sh and ./03_load_requirements.sh first."
  exit 1
fi
if ! "$PYTHON_BIN" -m mutmut --version >/dev/null 2>&1; then
  echo "mutmut is required in teller-venv but was not found."
  echo "Run ./03_load_requirements.sh to install test dependencies."
  exit 1
fi

MUTMUT_DARWIN_STUB="${REPO_ROOT}/scripts/mutmut_darwin_stub.py"
MUTMUT_DARWIN_DRIVER="${REPO_ROOT}/scripts/mutmut_darwin.py"
MUTATION_USE_SUBPROCESS="${MUTATION_USE_SUBPROCESS:-}"
if [ -z "$MUTATION_USE_SUBPROCESS" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    MUTATION_USE_SUBPROCESS=true
  else
    MUTATION_USE_SUBPROCESS=false
  fi
fi

#R010: Require unit tests to pass before mutation testing begins (unless explicitly skipped).
MUTATION_SKIP_PREFLIGHT="${MUTATION_SKIP_PREFLIGHT:-true}"
if [ "$MUTATION_SKIP_PREFLIGHT" = "true" ]; then
  echo ""
  echo "▶ Preflight: skipped (default; MUTATION_SKIP_PREFLIGHT=true)."
  echo "  Assumes ./10_run_python_unit_tests.sh already passed. To force pytest: MUTATION_SKIP_PREFLIGHT=false ./11_run_mutation_tests.sh"
else
  echo ""
  echo "▶ Preflight: running pytest on tests/py (MUTATION_SKIP_PREFLIGHT=false)."
  PREFLIGHT_OUTPUT="$(mktemp)"
  set +e
  (
    cd "$REPO_ROOT"
    PYTHONPATH="$REPO_ROOT" "$PYTHON_BIN" -m pytest "$PYTEST_DIR" -q
  ) > "$PREFLIGHT_OUTPUT" 2>&1
  PREFLIGHT_EXIT=$?
  set -e
  if [ "$PREFLIGHT_EXIT" -ne 0 ]; then
    echo "Unit tests failed. Fix tests first with: ./10_run_python_unit_tests.sh"
    cat "$PREFLIGHT_OUTPUT"
    exit 1
  fi
  echo "Preflight passed."
fi

#R040: Wrap mutmut execution with a configurable timeout.
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

print_runner_header \
  "mutmut" \
  "Python mutation testing for teller modules." \
  "Gates on mutation score and mutator coverage after mutmut run." \
  "https://mutmut.readthedocs.io/"

#R015: Run mutmut from repository root and export CI/CD stats.
if [ -d "${REPO_ROOT}/mutants" ]; then
  MUTANTS_TRASH="$(mktemp -d "${HOME}/.Trash/teller_mutants_XXXXXX")"
  mv "${REPO_ROOT}/mutants" "${MUTANTS_TRASH}/mutants"
fi
echo ""
if [ "$MUTATION_USE_SUBPROCESS" = "true" ]; then
  echo "▶ Running mutation tests (macOS subprocess driver; avoids mutmut fork+pytest SIGSEGV)..."
else
  echo "▶ Running mutation tests (mutmut)..."
fi
MUTMUT_OUTPUT="$(mktemp)"
set +e
export PATH="${REPO_ROOT}/teller-venv/bin:${PATH}"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
if [ "$MUTATION_USE_SUBPROCESS" = "true" ]; then
  run_with_timeout "$MUTATION_TIMEOUT_SECONDS" \
    "$PYTHON_BIN" "$MUTMUT_DARWIN_DRIVER" prepare --max-children 1 > "$MUTMUT_OUTPUT" 2>&1
  PREPARE_EXIT=$?
  if [ "$PREPARE_EXIT" -eq 0 ]; then
    export TELLER_PYTHON="$PYTHON_BIN"
    run_with_timeout "$MUTATION_TIMEOUT_SECONDS" \
      "$PYTHON_BIN" "$MUTMUT_DARWIN_DRIVER" execute >> "$MUTMUT_OUTPUT" 2>&1
    MUTMUT_EXIT=$?
  else
    MUTMUT_EXIT=$PREPARE_EXIT
  fi
else
  export PYTHONSTARTUP="${MUTMUT_DARWIN_STUB}"
  run_with_timeout "$MUTATION_TIMEOUT_SECONDS" \
    "$PYTHON_BIN" -m mutmut run --max-children 1 > "$MUTMUT_OUTPUT" 2>&1
  MUTMUT_EXIT=$?
  unset PYTHONSTARTUP
fi
set -e

if [ "$MUTMUT_EXIT" -eq 124 ]; then
  echo "Mutation testing timed out after ${MUTATION_TIMEOUT_SECONDS}s."
  exit 1
fi

mkdir -p "${REPO_ROOT}/mutants"
set +e
(
  cd "$REPO_ROOT"
  export PATH="${REPO_ROOT}/teller-venv/bin:${PATH}"
  "$PYTHON_BIN" -m mutmut export-cicd-stats >> "$MUTMUT_OUTPUT" 2>&1
)
EXPORT_EXIT=$?
set -e
if [ "$EXPORT_EXIT" -ne 0 ]; then
  echo "⚠️  mutmut export-cicd-stats exited ${EXPORT_EXIT}; continuing with any stats already on disk."
fi

if [ ! -s "$MUTMUT_CICD_STATS" ]; then
  echo "mutmut produced no results (no CI/CD stats JSON written)."
  echo "This usually means no covered mutants were found or the invocation is misconfigured."
  cat "$MUTMUT_OUTPUT"
  exit 1
fi

if [ "$MUTMUT_EXIT" -ne 0 ]; then
  echo "mutmut failed to execute (exit code ${MUTMUT_EXIT})."
  cat "$MUTMUT_OUTPUT"
  exit 1
fi

cp "$MUTMUT_CICD_STATS" "${REPORT_DIR}/mutmut-cicd-stats.json"

#R020: Parse mutmut stats and gate on score and mutator coverage thresholds.
#R022: Gate on mutator coverage so low-signal runs cannot pass on a tiny pool of verdicts.
#R030: Persist machine-readable mutation testing report.
#R035: Emit concise operator-readable pass or fail output.
"$PYTHON_BIN" - "$MUTMUT_CICD_STATS" "$MUTATION_SUMMARY" "$MUTATION_SCORE_THRESHOLD" "$MUTATOR_COVERAGE_THRESHOLD" "$MUTATION_EXCLUDE_FILES" "$REPO_ROOT" "$MUTMUT_OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

stats_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
score_threshold = float(sys.argv[3])
coverage_threshold = float(sys.argv[4])
excluded_files = [p.strip() for p in sys.argv[5].split(",") if p.strip()] if sys.argv[5] else []
repo_root = Path(sys.argv[6])
mutmut_log = Path(sys.argv[7])

data = json.loads(stats_path.read_text(encoding="utf-8"))
killed = int(data.get("killed", 0))
survived = int(data.get("survived", 0))
skipped = int(data.get("skipped", 0))
timed_out = int(data.get("timeout", 0))
no_tests = int(data.get("no_tests", 0))
suspicious = int(data.get("suspicious", 0))
segfault = int(data.get("segfault", 0))
total = int(data.get("total", killed + survived + skipped + timed_out + no_tests + suspicious + segfault))

by_module: dict[str, dict[str, int]] = {}
mutants_dir = repo_root / "mutants"
if mutants_dir.is_dir():
    for meta_path in sorted(mutants_dir.glob("**/*.meta")):
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        exit_codes = meta.get("exit_code_by_key", {})
        if not isinstance(exit_codes, dict):
            continue
        rel = meta_path.relative_to(mutants_dir)
        module_key = str(rel.with_suffix("")).replace(".meta", "").replace("\\", "/")
        if not module_key.startswith("teller"):
            parts = module_key.split("/")
            module_key = "/".join(parts[:2]) if len(parts) >= 2 else parts[0]
        entry = by_module.setdefault(
            module_key,
            {"killed": 0, "survived": 0, "skipped": 0, "timed_out": 0, "no_tests": 0},
        )
        for exit_code in exit_codes.values():
            status_map = {
                1: "killed",
                3: "killed",
                0: "survived",
                36: "timeout",
                24: "timeout",
                152: "timeout",
                255: "timeout",
                34: "skipped",
                33: "no_tests",
            }
            status = status_map.get(exit_code, "suspicious")
            if status in entry:
                entry[status] += 1

verdict_pool = killed + survived
not_checked = max(0, total - killed - survived - skipped - timed_out - no_tests - suspicious - segfault)
score = (killed / verdict_pool * 100.0) if verdict_pool > 0 else 0.0
mutator_coverage = (verdict_pool / total * 100.0) if total > 0 else 0.0
segfault_failed = segfault > 0 and verdict_pool == 0
incomplete_run = total > 0 and verdict_pool == 0
score_failed = incomplete_run or score < score_threshold
coverage_failed = total == 0 or mutator_coverage < coverage_threshold
gate_failed = score_failed or coverage_failed or segfault_failed

summary = {
    "total": total,
    "killed": killed,
    "survived": survived,
    "skipped": skipped,
    "timed_out": timed_out,
    "no_tests": no_tests,
    "suspicious": suspicious,
    "segfault": segfault,
    "not_checked": not_checked,
    "segfault_failed": segfault_failed,
    "incomplete_run": incomplete_run,
    "score": round(score, 2),
    "mutator_coverage": round(mutator_coverage, 2),
    "threshold": score_threshold,
    "coverage_threshold": coverage_threshold,
    "excluded_files": excluded_files,
    "score_failed": score_failed,
    "coverage_failed": coverage_failed,
    "gate_failed": gate_failed,
    "by_module": by_module,
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

for module_name, stats in sorted(by_module.items()):
    print(
        f"Mutation module {module_name}: "
        f"killed={stats['killed']} survived={stats['survived']} "
        f"skipped={stats['skipped']} timed_out={stats['timed_out']} no_tests={stats['no_tests']}"
    )

if segfault_failed:
    print(f"❌ FAIL: mutmut reported {segfault}/{total} segfaults and no killed/survived verdicts.")
if incomplete_run and not segfault_failed:
    print(f"❌ FAIL: mutmut did not execute mutants ({not_checked}/{total} still not checked).")
    if mutmut_log.exists():
        print("--- mutmut output (last 60 lines) ---")
        log_lines = mutmut_log.read_text(encoding="utf-8", errors="replace").splitlines()
        for line in log_lines[-60:]:
            print(line)
if score_failed and not incomplete_run:
    print(f"❌ FAIL: Mutation score {score:.2f}% is below threshold {score_threshold}%.")
if coverage_failed:
    print(f"❌ FAIL: Mutator coverage {mutator_coverage:.2f}% is below threshold {coverage_threshold}%.")
if gate_failed:
    raise SystemExit(1)
print(
    f"✅ PASS: Mutation score {score:.2f}% (threshold {score_threshold}%), "
    f"mutator coverage {mutator_coverage:.2f}% (threshold {coverage_threshold}%)."
)
PY

echo ""
echo "Mutation testing completed. Report: ${MUTATION_SUMMARY}"
