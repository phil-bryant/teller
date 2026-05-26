#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
}

teardown() {
  teardown_shell_test
}

@test "exports canonical cache locations under artifacts/cache" {
  #R001-T01
  run bash -c "
    # shellcheck disable=SC1091
    source '${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh'
    export_test_cache_env '${FIXTURE_ROOT}'
    printf 'CACHE_ROOT=%s\nPYTHONPYCACHEPREFIX=%s\nRUFF_CACHE_DIR=%s\n' \
      \"\${CACHE_ROOT}\" \"\${PYTHONPYCACHEPREFIX}\" \"\${RUFF_CACHE_DIR}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifacts/cache"* ]]
  [[ "$output" == *"pycache"* ]]
  [[ "$output" == *"ruff"* ]]
  [ -d "${FIXTURE_ROOT}/artifacts/cache/pycache" ]
  [ -d "${FIXTURE_ROOT}/artifacts/cache/ruff" ]
}

@test "defaults hypothesis storage away from repository root" {
  #R005-T01
  run bash -c "
    unset HYPOTHESIS_STORAGE_DIRECTORY
    # shellcheck disable=SC1091
    source '${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh'
    export_test_cache_env '${FIXTURE_ROOT}'
    printf '%s' \"\${HYPOTHESIS_STORAGE_DIRECTORY}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifacts/cache/hypothesis"* ]]
  [[ "$output" != *".hypothesis"* ]]
}
