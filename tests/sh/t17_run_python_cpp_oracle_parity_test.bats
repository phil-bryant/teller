#!/usr/bin/env bats
# Self-contained shell unit tests for tests/t17_run_python_cpp_oracle_parity_test.sh,
# the teller-owned Python/C++ oracle parity lane. These assert its preflight,
# build, and snapshot-diff contract.

#R001: function tag for setup
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd -P)"
  SCRIPT="${REPO_ROOT}/tests/t17_run_python_cpp_oracle_parity_test.sh"
}

@test "lane requires the teller-venv interpreter" {
  #R001-T01: venv python preflight with remediation message.
  run grep -q 'VENV_PY="\${REPO_ROOT}/teller-venv/bin/python3"' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'teller-venv missing' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "lane builds the C++ oracle runner" {
  #R005-T01: builds the teller_oracle_runner target.
  run grep -q 'cmake --build "\${BUILD_DIR}" .* --target teller_oracle_runner' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "lane diffs python vs C++ full-database snapshots" {
  #R010-T01: runs compare_oracle.py against the built runner.
  run grep -q 'compare_oracle.py' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q -- '--runner "\${BUILD_DIR}/teller_oracle_runner"' "$SCRIPT"
  [ "$status" -eq 0 ]
}
