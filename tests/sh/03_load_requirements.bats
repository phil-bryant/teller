#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "03_load_requirements.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails when expected venv directory is missing" {
  #R001
  run bash -c "cd '${FIXTURE_ROOT}' && ./03_load_requirements.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"02_create_venv.sh"* ]]
  [[ "$output" == *"Virtual environment not found!"* ]]
}

@test "fails when no virtual environment is active" {
  #R005
  mkdir -p "${FIXTURE_ROOT}/fixture-venv"
  run bash -c "cd '${FIXTURE_ROOT}' && unset VIRTUAL_ENV && ./03_load_requirements.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No virtual environment is currently active!"* ]]
  [[ "$output" == *"bin/activate"* ]]
}

@test "fails when active venv does not match project venv" {
  #R010
  mkdir -p "${FIXTURE_ROOT}/fixture-venv" "${TEST_TMPDIR}/other-venv"
  run bash -c "cd '${FIXTURE_ROOT}' && export VIRTUAL_ENV='${TEST_TMPDIR}/other-venv' && ./03_load_requirements.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"different virtual environment"* ]]
}

@test "prefers requirements.txt when present" {
  #R015 #R025
  local venv
  venv="${FIXTURE_ROOT}/fixture-venv"
  mkdir -p "${venv}/bin"
  touch "${FIXTURE_ROOT}/requirements.txt"
  cat > "${venv}/pyvenv.cfg" <<EOF
home = /usr
include-system-site-packages = false
version = 3.12.0
EOF
  stub_cmd pip3 "echo pip3 \"\$*\" >> \"${CALLS_LOG}\"; exit 0"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export VIRTUAL_ENV=\"\$(cd '${FIXTURE_ROOT}/fixture-venv' && pwd -P)\" && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    ./03_load_requirements.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requirements.txt"* ]]
  grep -F "install --upgrade pip" "${CALLS_LOG}"
  grep -F "install -r requirements.txt" "${CALLS_LOG}"
}

@test "requires cpu or gpu when split files are used" {
  #R020
  local venv
  venv="${FIXTURE_ROOT}/fixture-venv"
  mkdir -p "${venv}/bin"
  echo ok > "${FIXTURE_ROOT}/requirements-cpu.txt"
  echo ok > "${FIXTURE_ROOT}/requirements-gpu.txt"
  cat > "${venv}/pyvenv.cfg" <<EOF
home = /usr
include-system-site-packages = false
version = 3.12.0
EOF
  stub_cmd pip3 "echo pip3 \"\$*\" >> \"${CALLS_LOG}\"; exit 0"
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export VIRTUAL_ENV=\"\$(cd '${FIXTURE_ROOT}/fixture-venv' && pwd -P)\" && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    ./03_load_requirements.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required parameter"* || "$output" == *"Error:"* ]]
  run bash -c "cd '${FIXTURE_ROOT}' && \
    export VIRTUAL_ENV=\"\$(cd '${FIXTURE_ROOT}/fixture-venv' && pwd -P)\" && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    ./03_load_requirements.sh oops"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid parameter"* || "$output" == *"Error:"* ]]
}

@test "03_load_requirements is locked and excluded from automatic tag pairing" {
  #R030
  local real_script
  real_script="$(repo_root)/03_load_requirements.sh"
  [ -f "$real_script" ]
  grep -q "DO_NOT_MODIFY_THIS_FILE" "$real_script"
  grep -q "<AI_MODEL_INSTRUCTION>" "$real_script"
  run bash -c "cd '$(repo_root)' && ./00_run_requirements_traceability_tests.sh requirements/03_load_requirements-requirements.md 03_load_requirements.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (locked-policy)"* ]]
}

@test "requirements pin wheel-based psycopg2 dependency" {
  #R035
  local req_file
  req_file="$(repo_root)/requirements.txt"
  run grep -E '^psycopg2-binary(==.*)?$' "$req_file"
  [ "$status" -eq 0 ]
  run grep -E '^psycopg2(==.*)?$' "$req_file"
  [ "$status" -ne 0 ]
}
