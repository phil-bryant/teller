#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
}

teardown() {
  teardown_shell_test
}

@test "leaves PYTEST_ADDOPTS unchanged without invalid cache-dir flag" {
  #R001-T01
  run bash -c "
    export PYTEST_ADDOPTS='-q --maxfail=1'
    source '${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh'
    printf '%s' \"\${PYTEST_ADDOPTS}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "-q --maxfail=1" ]
}

@test "strips invalid --cache-dir from PYTEST_ADDOPTS" {
  #R005-T01
  run bash -c "
    export PYTEST_ADDOPTS='--cache-dir=./artifacts/cache/pytest -q'
    source '${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh'
    printf '%s' \"\${PYTEST_ADDOPTS:-}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"--cache-dir="* ]]
  [[ "$output" == *"-q"* ]]
  [[ "$output" == *"Stripping invalid --cache-dir"* ]]
}
