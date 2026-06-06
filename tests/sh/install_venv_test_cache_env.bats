#!/usr/bin/env bats

load "helpers/common.bash"

#R001: Prepare bats fixture state for script-level verification tests.
setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/install_venv_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/install_venv_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  touch "${FIXTURE_ROOT}/pyproject.toml"
}

#R001: Cleanup bats fixture state after script-level verification tests.
teardown() {
  teardown_shell_test
}

@test "appends teller cache marker to activate script idempotently" {
  #R001-T01: Verify activate script contains exactly one teller cache marker after two install calls.
  mkdir -p "${FIXTURE_ROOT}/fixture-venv/bin"
  cat > "${FIXTURE_ROOT}/fixture-venv/bin/activate" <<'EOF'
# minimal activate stub
EOF

  run bash -c "
    bash '${FIXTURE_ROOT}/src/scripts/install_venv_test_cache_env.sh' '${FIXTURE_ROOT}/fixture-venv'
    bash '${FIXTURE_ROOT}/src/scripts/install_venv_test_cache_env.sh' '${FIXTURE_ROOT}/fixture-venv'
    grep -c '# >>> teller test cache env >>>' '${FIXTURE_ROOT}/fixture-venv/bin/activate'
  "
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "fails when activate script is missing" {
  #R005-T01: Verify missing activate script produces an explicit failure message.
  run bash -c "
    bash '${FIXTURE_ROOT}/src/scripts/install_venv_test_cache_env.sh' '${FIXTURE_ROOT}/missing-venv'
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"activate script not found"* ]]
}
