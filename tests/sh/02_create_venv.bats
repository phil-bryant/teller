#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  unset VIRTUAL_ENV
  create_repo_fixture
  copy_script_to_fixture "02_create_venv.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/install_venv_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/install_venv_test_cache_env.sh"
  touch "${FIXTURE_ROOT}/pyproject.toml"
  mkdir -p "${FIXTURE_ROOT}/tests/py"
}

teardown() {
  teardown_shell_test
}

@test "fails when sibling prerequisites script is missing" {
  #R001-T01 #R005-T01
  run bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Prerequisites script not found"* ]]
}

@test "prefers python3.12 when both interpreters exist" {
  #R010-T01 #R010-T02 #R035-T01 #R038-T01
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  cat > "${STUB_BIN}/python3.12" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  mkdir -p "$3/bin"
  touch "$3/bin/activate"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/python3.12"
  stub_cmd python3 "exit 0"

  run bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created virtual environment"* ]]
  [ -f "${FIXTURE_ROOT}/fixture-venv/bin/activate" ]
  grep -Fq '# >>> teller test cache env >>>' "${FIXTURE_ROOT}/fixture-venv/bin/activate"
}

@test "refuses to run while another virtualenv is active" {
  #R015-T01 #R025-T01
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  stub_cmd python3 "exit 0"

  run env VIRTUAL_ENV="/tmp/other-venv" bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"A virtual environment is currently active"* ]]
}

@test "returns success without recreating existing venv directory" {
  #R020-T01 #R030-T01 #R040-T01
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  mkdir -p "${FIXTURE_ROOT}/fixture-venv/bin"
  touch "${FIXTURE_ROOT}/fixture-venv/bin/activate"
  stub_cmd python3 "echo unexpected-python-call; exit 1"

  run bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Virtual environment already exists"* ]]
}
