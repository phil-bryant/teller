#!/usr/bin/env bash
# Oracle parity lane (M3): drives every persist scenario through BOTH the
# Python reference (teller.teller_persist via teller-venv) and the C++ core
# (teller_oracle_runner), diffing normalized full-database snapshots.
# Self-contained (no runner delegation): the C++ core is teller-owned.
#
# Postgres parity runs additionally when TELLER_PARITY_PG_ADMIN_CONNINFO is
# exported (libpq keyword conninfo with CREATE DATABASE permission).
set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE_DIR="${REPO_ROOT}/src/core"
# Lane-private build tree: parallel lanes must not race t15's cmake configure.
BUILD_DIR="${CORE_DIR}/build-parity"
VENV_PY="${REPO_ROOT}/teller-venv/bin/python3"

if [[ ! -x "${VENV_PY}" ]]; then
  echo "t17: teller-venv missing (run ./02_create_venv.sh && ./04_load_requirements.sh)" >&2
  exit 2
fi

cmake -S "${CORE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)" --target teller_oracle_runner >/dev/null

"${VENV_PY}" "${CORE_DIR}/oracle/compare_oracle.py" \
  --runner "${BUILD_DIR}/teller_oracle_runner"
echo "t17: Python/C++ oracle parity passed"
