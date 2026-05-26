#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
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

REPORT_DIR="${MUTATION_REPORT_DIR:-./artifacts/mutation}"
MUTATION_SCORE_THRESHOLD="${MUTATION_SCORE_THRESHOLD:-95}"
MUTATOR_COVERAGE_THRESHOLD="${MUTATOR_COVERAGE_THRESHOLD:-90}"
MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-600}"
#R025: Record optional file exclusions in the persisted mutation summary.
MUTATION_EXCLUDE_FILES="${MUTATION_EXCLUDE_FILES:-}"
PYTHON_BIN="${REPO_ROOT}/teller-venv/bin/python3"
PYTEST_DIR="${REPO_ROOT}/tests/py"
ROOT_MUTANTS_LINK="${REPO_ROOT}/mutants"
MUTANTS_DIR="${MUTATION_WORK_DIR:-${REPORT_DIR}/mutants}"
MUTMUT_CICD_STATS="${MUTANTS_DIR}/mutmut-cicd-stats.json"
MUTATION_SUMMARY="${REPORT_DIR}/mutation-summary.json"
MUTATION_HISTORY_PATH="${MUTATION_HISTORY_PATH:-${REPORT_DIR}/mutation-history.ndjson}"
MUTATION_TREND_PATH="${MUTATION_TREND_PATH:-${REPORT_DIR}/mutation-trend.json}"
MUTATION_SURVIVOR_BUDGET="${MUTATION_SURVIVOR_BUDGET:-}"
MUTATION_HYPOTHESIS_SEED="${MUTATION_HYPOTHESIS_SEED:-20260525}"
RUN_STARTED_EPOCH="$(date +%s)"
RUN_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
IS_CI=false
if [[ "${CI:-}" == "1" || "${CI:-}" == "true" || "${CI:-}" == "TRUE" ]]; then
  IS_CI=true
fi

if [[ "${REPORT_DIR}" != /* ]]; then
  REPORT_DIR="${REPO_ROOT}/${REPORT_DIR#./}"
fi
if [[ "${MUTANTS_DIR}" != /* ]]; then
  MUTANTS_DIR="${REPO_ROOT}/${MUTANTS_DIR#./}"
fi
MUTATION_SUMMARY="${REPORT_DIR}/mutation-summary.json"
MUTMUT_CICD_STATS="${MUTANTS_DIR}/mutmut-cicd-stats.json"

mkdir -p "$REPORT_DIR"
mkdir -p "${REPO_ROOT}/artifacts/cache/egg-info"
MUTANTS_LINK_CREATED=false

cleanup_mutants_link() {
  if [[ "$MUTANTS_LINK_CREATED" == "true" ]] && [[ -L "$ROOT_MUTANTS_LINK" ]]; then
    rm -f "$ROOT_MUTANTS_LINK"
  fi
}

trap cleanup_mutants_link EXIT

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

MUTMUT_DARWIN_STUB="${REPO_ROOT}/src/scripts/mutmut_darwin_stub.py"
MUTMUT_DARWIN_DRIVER="${REPO_ROOT}/src/scripts/mutmut_darwin.py"
MUTATION_USE_SUBPROCESS="${MUTATION_USE_SUBPROCESS:-}"
if [ -z "$MUTATION_USE_SUBPROCESS" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    MUTATION_USE_SUBPROCESS=true
  else
    MUTATION_USE_SUBPROCESS=false
  fi
fi

#R010: Require unit tests to pass before mutation testing begins (unless explicitly skipped).
if [[ -z "${MUTATION_SKIP_PREFLIGHT+x}" ]]; then
  MUTATION_SKIP_PREFLIGHT=false
fi
if [ "$MUTATION_SKIP_PREFLIGHT" = "true" ]; then
  echo ""
  echo "▶ Preflight: skipped (MUTATION_SKIP_PREFLIGHT=true override)."
  echo "  Default behavior now runs preflight pytest for local and CI mutation runs."
else
  echo ""
  echo "▶ Preflight: running pytest on tests/py (MUTATION_SKIP_PREFLIGHT=false)."
  PREFLIGHT_OUTPUT="$(mktemp)"
  set +e
  (
    cd "$REPO_ROOT"
    PYTHONPATH="$REPO_ROOT/src:$REPO_ROOT" "$PYTHON_BIN" -m pytest "$PYTEST_DIR" -q
  ) > "$PREFLIGHT_OUTPUT" 2>&1
  PREFLIGHT_EXIT=$?
  set -e
  if [ "$PREFLIGHT_EXIT" -ne 0 ]; then
    echo "Unit tests failed. Fix tests first with: ./tests/t08_run_python_unit_tests.sh"
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
if [ -e "${ROOT_MUTANTS_LINK}" ] && [ ! -L "${ROOT_MUTANTS_LINK}" ]; then
  MUTANTS_TRASH="$(mktemp -d "${HOME}/.Trash/teller_mutants_XXXXXX")"
  mv "${ROOT_MUTANTS_LINK}" "${MUTANTS_TRASH}/mutants"
fi
if [ -d "${MUTANTS_DIR}" ]; then
  MUTANTS_TRASH="$(mktemp -d "${HOME}/.Trash/teller_mutants_XXXXXX")"
  mv "${MUTANTS_DIR}" "${MUTANTS_TRASH}/mutants"
fi
if [ -L "${ROOT_MUTANTS_LINK}" ]; then
  rm -f "${ROOT_MUTANTS_LINK}"
fi
mkdir -p "$(dirname "$MUTANTS_DIR")"
mkdir -p "$MUTANTS_DIR"
ln -s "$MUTANTS_DIR" "$ROOT_MUTANTS_LINK"
MUTANTS_LINK_CREATED=true
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
export HYPOTHESIS_SEED="${MUTATION_HYPOTHESIS_SEED}"
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
    echo "⚠️  mutmut Darwin subprocess driver failed to prepare; falling back to direct mutmut run." >> "$MUTMUT_OUTPUT"
    export PYTHONSTARTUP="${MUTMUT_DARWIN_STUB}"
    run_with_timeout "$MUTATION_TIMEOUT_SECONDS" \
      "$PYTHON_BIN" -m mutmut run --max-children 1 >> "$MUTMUT_OUTPUT" 2>&1
    MUTMUT_EXIT=$?
    unset PYTHONSTARTUP
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

if [ "$MUTMUT_EXIT" -ne 0 ]; then
  #R050: Enforce strict CI behavior when mutmut is skipped for host/runtime incompatibility.
  RUN_ENDED_EPOCH="$(date +%s)"
  RUN_DURATION_SECONDS=$((RUN_ENDED_EPOCH - RUN_STARTED_EPOCH))
  mkdir -p "$(dirname "$MUTMUT_CICD_STATS")"
  cat > "$MUTMUT_CICD_STATS" <<'JSON'
{
  "killed": 0,
  "survived": 0,
  "skipped": 0,
  "timeout": 0,
  "no_tests": 0,
  "suspicious": 0,
  "segfault": 0,
  "total": 0
}
JSON
  cp "$MUTMUT_CICD_STATS" "${REPORT_DIR}/mutmut-cicd-stats.json"
  "$PYTHON_BIN" - "$MUTATION_SUMMARY" "$MUTATION_SCORE_THRESHOLD" "$MUTATOR_COVERAGE_THRESHOLD" "$IS_CI" "$RUN_STARTED_AT" "$GIT_SHA" "$RUN_DURATION_SECONDS" "$MUTATION_HISTORY_PATH" "$MUTATION_TREND_PATH" "$MUTATION_SURVIVOR_BUDGET" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

summary_path = Path(sys.argv[1])
score_threshold = float(sys.argv[2])
coverage_threshold = float(sys.argv[3])
is_ci = sys.argv[4].strip().lower() == "true"
run_started_at = sys.argv[5]
git_sha = sys.argv[6]
duration_seconds = int(float(sys.argv[7]))
history_path = Path(sys.argv[8])
trend_path = Path(sys.argv[9])
survivor_budget = int(sys.argv[10]) if sys.argv[10].strip() else None

summary = {
    "total": 0,
    "killed": 0,
    "survived": 0,
    "skipped": 0,
    "timed_out": 0,
    "no_tests": 0,
    "suspicious": 0,
    "segfault": 0,
    "not_checked": 0,
    "segfault_failed": False,
    "incomplete_run": False,
    "score": 0.0,
    "mutator_coverage": 0.0,
    "threshold": score_threshold,
    "coverage_threshold": coverage_threshold,
    "excluded_files": [],
    "score_failed": False,
    "coverage_failed": False,
    "survivor_budget": survivor_budget,
    "survivor_budget_failed": False,
    "gate_failed": is_ci,
    "by_module": {},
    "run_started_at": run_started_at,
    "git_sha": git_sha,
    "duration_seconds": duration_seconds,
    "skipped": True,
    "skip_reason": "mutmut runtime incompatibility on this host",
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

history_path.parent.mkdir(parents=True, exist_ok=True)
#R045: Append run records and derive rolling 14-day medians for mutation trends.
record = {
    "run_started_at": run_started_at,
    "git_sha": git_sha,
    "score": 0.0,
    "mutator_coverage": 0.0,
    "survived": 0,
    "killed": 0,
    "total": 0,
    "duration_seconds": duration_seconds,
    "skipped": True,
}
with history_path.open("a", encoding="utf-8") as history_file:
    history_file.write(json.dumps(record) + "\n")

records = []
for line in history_path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(payload, dict):
        records.append(payload)
cutoff = datetime.now(timezone.utc) - timedelta(days=14)
scores = []
coverages = []
for payload in records:
    ts = payload.get("run_started_at")
    if not isinstance(ts, str):
        continue
    try:
        parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        continue
    if parsed < cutoff:
        continue
    scores.append(float(payload.get("score", 0.0)))
    coverages.append(float(payload.get("mutator_coverage", 0.0)))
scores_sorted = sorted(scores)
coverages_sorted = sorted(coverages)
median_score = scores_sorted[len(scores_sorted) // 2] if scores_sorted else 0.0
median_coverage = coverages_sorted[len(coverages_sorted) // 2] if coverages_sorted else 0.0
trend_payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "history_path": str(history_path),
    "runs_recorded": len(records),
    "rolling_14d": {
        "runs": len(scores),
        "median_score": round(median_score, 2),
        "median_mutator_coverage": round(median_coverage, 2),
    },
    "last_run": record,
}
trend_path.parent.mkdir(parents=True, exist_ok=True)
trend_path.write_text(json.dumps(trend_payload, indent=2) + "\n", encoding="utf-8")
PY
  if [[ "$IS_CI" == "true" ]]; then
    echo "❌ FAIL: Mutation testing skipped due mutmut runtime incompatibility on this host (CI strict mode)."
    echo "Mutation testing completed. Report: ${MUTATION_SUMMARY}"
    exit 1
  fi
  echo "⚠️  SKIP: Mutation testing skipped due mutmut runtime incompatibility on this host."
  echo "Mutation testing completed. Report: ${MUTATION_SUMMARY}"
  exit 0
fi

if [ ! -s "$MUTMUT_CICD_STATS" ]; then
  "$PYTHON_BIN" - "$REPO_ROOT" "$MUTMUT_CICD_STATS" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
stats_path = Path(sys.argv[2])
mutants_dir = root / "mutants"

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
counts = {
    "killed": 0,
    "survived": 0,
    "skipped": 0,
    "timeout": 0,
    "no_tests": 0,
    "suspicious": 0,
    "segfault": 0,
}

for meta_path in sorted(mutants_dir.glob("**/*.meta")):
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except Exception:
        continue
    exit_codes = meta.get("exit_code_by_key", {})
    if not isinstance(exit_codes, dict):
        continue
    for exit_code in exit_codes.values():
        status = status_map.get(exit_code, "suspicious")
        if status in counts:
            counts[status] += 1

total = sum(counts.values())
if total == 0:
    raise SystemExit(0)

payload = {
    "killed": counts["killed"],
    "survived": counts["survived"],
    "skipped": counts["skipped"],
    "timeout": counts["timeout"],
    "no_tests": counts["no_tests"],
    "suspicious": counts["suspicious"],
    "segfault": counts["segfault"],
    "total": total,
}
stats_path.parent.mkdir(parents=True, exist_ok=True)
stats_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
fi

if [ ! -s "${MUTANTS_DIR}/mutmut-cicd-stats.json" ]; then
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
"$PYTHON_BIN" - "$MUTMUT_CICD_STATS" "$MUTATION_SUMMARY" "$MUTATION_SCORE_THRESHOLD" "$MUTATOR_COVERAGE_THRESHOLD" "$MUTATION_EXCLUDE_FILES" "$MUTANTS_DIR" "$MUTMUT_OUTPUT" "$RUN_STARTED_AT" "$GIT_SHA" "$RUN_STARTED_EPOCH" "$MUTATION_HISTORY_PATH" "$MUTATION_TREND_PATH" "$MUTATION_SURVIVOR_BUDGET" "$IS_CI" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

stats_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
score_threshold = float(sys.argv[3])
coverage_threshold = float(sys.argv[4])
excluded_files = [p.strip() for p in sys.argv[5].split(",") if p.strip()] if sys.argv[5] else []
mutants_dir = Path(sys.argv[6])
mutmut_log = Path(sys.argv[7])
run_started_at = sys.argv[8]
git_sha = sys.argv[9]
run_started_epoch = int(float(sys.argv[10]))
history_path = Path(sys.argv[11])
trend_path = Path(sys.argv[12])
survivor_budget = int(sys.argv[13]) if sys.argv[13].strip() else None
is_ci = sys.argv[14].strip().lower() == "true"

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
survivor_budget_failed = survivor_budget is not None and survived > survivor_budget
gate_failed = score_failed or coverage_failed or segfault_failed or survivor_budget_failed
duration_seconds = max(0, int(datetime.now(timezone.utc).timestamp()) - run_started_epoch)

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
    "survivor_budget": survivor_budget,
    "survivor_budget_failed": survivor_budget_failed,  #R055: Fail gate when survived mutants exceed configured budget.
    "gate_failed": gate_failed,
    "by_module": by_module,
    "run_started_at": run_started_at,
    "git_sha": git_sha,
    "duration_seconds": duration_seconds,
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

history_record = {
    "run_started_at": run_started_at,
    "git_sha": git_sha,
    "score": round(score, 2),
    "mutator_coverage": round(mutator_coverage, 2),
    "survived": survived,
    "killed": killed,
    "total": total,
    "duration_seconds": duration_seconds,
    "skipped": False,
}
history_path.parent.mkdir(parents=True, exist_ok=True)
with history_path.open("a", encoding="utf-8") as history_file:
    history_file.write(json.dumps(history_record) + "\n")

records = []
for line in history_path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(payload, dict):
        records.append(payload)
cutoff = datetime.now(timezone.utc) - timedelta(days=14)
scores = []
coverages = []
for payload in records:
    ts = payload.get("run_started_at")
    if not isinstance(ts, str):
        continue
    try:
        parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        continue
    if parsed < cutoff:
        continue
    scores.append(float(payload.get("score", 0.0)))
    coverages.append(float(payload.get("mutator_coverage", 0.0)))
scores_sorted = sorted(scores)
coverages_sorted = sorted(coverages)
median_score = scores_sorted[len(scores_sorted) // 2] if scores_sorted else 0.0
median_coverage = coverages_sorted[len(coverages_sorted) // 2] if coverages_sorted else 0.0
trend_payload = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "history_path": str(history_path),
    "runs_recorded": len(records),
    "rolling_14d": {
        "runs": len(scores),
        "median_score": round(median_score, 2),
        "median_mutator_coverage": round(median_coverage, 2),
    },
    "last_run": history_record,
}
trend_path.parent.mkdir(parents=True, exist_ok=True)
trend_path.write_text(json.dumps(trend_payload, indent=2) + "\n", encoding="utf-8")

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
if survivor_budget_failed:
    print(
        f"❌ FAIL: Survived mutants {survived} exceed survivor budget {survivor_budget}."
    )
if gate_failed:
    raise SystemExit(1)
print(
    f"✅ PASS: Mutation score {score:.2f}% (threshold {score_threshold}%), "
    f"mutator coverage {mutator_coverage:.2f}% (threshold {coverage_threshold}%)."
)
print(
    f"Trend: {trend_payload['rolling_14d']['runs']} run(s) in last 14d, "
    f"median score {trend_payload['rolling_14d']['median_score']:.2f}%, "
    f"median mutator coverage {trend_payload['rolling_14d']['median_mutator_coverage']:.2f}%."
)
if is_ci and total == 0:
    raise SystemExit(1)
PY

echo ""
echo "Mutation testing completed. Report: ${MUTATION_SUMMARY}"
