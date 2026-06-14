#!/usr/bin/env bash
# C++ core lane: configure + build tellercore and run the Catch2 unit suite.
# Self-contained (no runner delegation): the C++ core is teller-owned.
# PostgreSQL-tagged cases skip unless TELLER_TEST_PG_CONNINFO is exported
# (the t18 lane provisions a scratch database and runs them for real).
set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE_DIR="${REPO_ROOT}/src/core"
BUILD_DIR="${CORE_DIR}/build"

#R001: Configure and build the teller-owned C++ core in RelWithDebInfo.
cmake -S "${CORE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)" >/dev/null
#R005: Run the Catch2 C++ core unit suite (postgres-tagged cases skip without TELLER_TEST_PG_CONNINFO).
"${BUILD_DIR}/tellercore_tests"
echo "t15: C++ core unit tests passed"
