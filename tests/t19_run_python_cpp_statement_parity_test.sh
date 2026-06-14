#!/usr/bin/env bash
# Statement parsing parity lane (M3): drives every statement scenario through
# BOTH the Python reference (08_backfill_bank_statements functions via
# teller-venv) and the C++ core (teller_oracle_runner replay-statements),
# diffing parsed transaction lists, deterministic ids, period, and summary
# totals. OCR is excluded -- parity runs at the parser boundary on canned OCR
# observation fixtures so the drift-prone logic is verified deterministically.
# Self-contained (no runner delegation): the C++ core is teller-owned.
set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE_DIR="${REPO_ROOT}/src/core"
# Lane-private build tree: parallel lanes must not race t15's cmake configure.
BUILD_DIR="${CORE_DIR}/build-parity"
VENV_PY="${REPO_ROOT}/teller-venv/bin/python3"

if [[ ! -x "${VENV_PY}" ]]; then
  echo "t19: teller-venv missing (run ./02_create_venv.sh && ./04_load_requirements.sh)" >&2
  exit 2
fi

cmake -S "${CORE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)" --target teller_oracle_runner >/dev/null

"${VENV_PY}" "${CORE_DIR}/oracle/compare_statement_oracle.py" \
  --runner "${BUILD_DIR}/teller_oracle_runner"
echo "t19: Python/C++ statement parsing parity passed"
