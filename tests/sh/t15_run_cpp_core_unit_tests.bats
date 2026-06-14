#!/usr/bin/env bats
# Self-contained shell unit tests for tests/t15_run_cpp_core_unit_tests.sh,
# the teller-owned C++ core unit lane. These assert its build + run contract.

#R001: function tag for setup
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd -P)"
  SCRIPT="${REPO_ROOT}/tests/t15_run_cpp_core_unit_tests.sh"
}

@test "lane configures and builds the C++ core in RelWithDebInfo" {
  #R001-T01: cmake configure (RelWithDebInfo) and build of the C++ core.
  run grep -q 'cmake -S "\${CORE_DIR}" -B "\${BUILD_DIR}" -DCMAKE_BUILD_TYPE=RelWithDebInfo' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'cmake --build "\${BUILD_DIR}"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "lane runs the Catch2 C++ core unit suite" {
  #R005-T01: runs tellercore_tests and reports a passing marker.
  run grep -q '"\${BUILD_DIR}/tellercore_tests"' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 't15: C++ core unit tests passed' "$SCRIPT"
  [ "$status" -eq 0 ]
}
