#!/usr/bin/env bats
# Self-contained shell unit tests for tests/t16_run_cpp_core_sanitizer_tests.sh,
# the teller-owned C++ core sanitizer lane. These assert its ASan/UBSan contract.

#R001: function tag for setup
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd -P)"
  SCRIPT="${REPO_ROOT}/tests/t16_run_cpp_core_sanitizer_tests.sh"
}

@test "lane rebuilds the C++ core with sanitizers enabled" {
  #R001-T01: sanitizer build configuration (TELLERCORE_SANITIZE=ON, Debug) and build.
  run grep -q 'DTELLERCORE_SANITIZE=ON' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'DCMAKE_BUILD_TYPE=Debug' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'cmake --build "\${BUILD_DIR}"' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "lane reruns the unit suite under sanitizers with halt-on-error" {
  #R005-T01: UBSAN_OPTIONS halt_on_error gating on the suite run.
  run grep -q 'UBSAN_OPTIONS=halt_on_error=1 "\${BUILD_DIR}/tellercore_tests"' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 't16: C++ core sanitizer tests passed' "$SCRIPT"
  [ "$status" -eq 0 ]
}
