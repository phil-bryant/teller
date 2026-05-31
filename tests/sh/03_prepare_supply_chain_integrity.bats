#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "03_prepare_supply_chain_integrity.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts/security"
  cp "$(repo_root)/src/scripts/security/generate_supply_chain_artifacts.py" \
    "${FIXTURE_ROOT}/src/scripts/security/generate_supply_chain_artifacts.py"
}

teardown() {
  teardown_shell_test
}

@test "script exists and is executable" {
  #R001-T01
  [ -x "${FIXTURE_ROOT}/03_prepare_supply_chain_integrity.sh" ]
}

@test "fails when project venv is missing" {
  #R005-T01
  run bash -c "cd '${FIXTURE_ROOT}' && ./03_prepare_supply_chain_integrity.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Virtual environment not found"* ]]
}

@test "fails when active venv is missing" {
  #R005-T02
  mkdir -p "${FIXTURE_ROOT}/fixture-venv"
  run bash -c "cd '${FIXTURE_ROOT}' && unset VIRTUAL_ENV && ./03_prepare_supply_chain_integrity.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No virtual environment is currently active"* ]]
}

@test "runs pip-tools compile with hashes for runtime and security lockfiles and invokes artifact generator" {
  #R010-T01 #R010-T02 #R015-T01
  mkdir -p "${FIXTURE_ROOT}/fixture-venv" "${FIXTURE_ROOT}/requirements/security"
  cat > "${FIXTURE_ROOT}/fixture-venv/pyvenv.cfg" <<'EOF'
home = /usr
include-system-site-packages = false
version = 3.12.0
EOF
  cat > "${FIXTURE_ROOT}/requirements.in" <<'EOF'
requests==2.34.2
EOF
  cat > "${FIXTURE_ROOT}/requirements/security/requirements-security.in" <<'EOF'
bandit==1.9.4
EOF

  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
echo "python3 $*" >> "${CALLS_LOG}"
if [[ "$1" == "-m" && "$2" == "pip" && "$3" == "show" && "$4" == "pip-tools" ]]; then
  exit 1
fi
if [[ "$1" == "./src/scripts/security/generate_supply_chain_artifacts.py" ]]; then
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "${STUB_BIN}/python3"

  cat > "${STUB_BIN}/pip-compile" <<'EOF'
#!/usr/bin/env bash
echo "pip-compile $*" >> "${CALLS_LOG}"
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--output-file" ]]; then
    out="$arg"
    break
  fi
  prev="$arg"
done
if [[ -n "$out" ]]; then
  cat > "$out" <<'OUT'
requests==2.34.2 \
    --hash=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OUT
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/pip-compile"

  run bash -c "cd '${FIXTURE_ROOT}' && \
    export VIRTUAL_ENV=\"\$(cd '${FIXTURE_ROOT}/fixture-venv' && pwd -P)\" && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    ./03_prepare_supply_chain_integrity.sh"
  [ "$status" -eq 0 ]

  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"pip-compile --generate-hashes --resolver=backtracking --output-file ./requirements.txt ./requirements.in"* ]]
  [[ "$calls" == *"pip-compile --generate-hashes --resolver=backtracking --output-file ./requirements/security/requirements-security.txt ./requirements/security/requirements-security.in"* ]]
  [[ "$calls" == *"python3 ./src/scripts/security/generate_supply_chain_artifacts.py --runtime-lock ./requirements.txt --security-lock ./requirements/security/requirements-security.txt --output-dir ./artifacts/security/reports --signing-mode scaffold"* ]]
}

@test "defaults supply-chain signing mode to required in CI when unset" {
  #R020-T01
  mkdir -p "${FIXTURE_ROOT}/fixture-venv" "${FIXTURE_ROOT}/requirements/security"
  cat > "${FIXTURE_ROOT}/fixture-venv/pyvenv.cfg" <<'EOF'
home = /usr
include-system-site-packages = false
version = 3.12.0
EOF
  cat > "${FIXTURE_ROOT}/requirements.in" <<'EOF'
requests==2.34.2
EOF
  cat > "${FIXTURE_ROOT}/requirements/security/requirements-security.in" <<'EOF'
bandit==1.9.4
EOF

  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
echo "python3 $*" >> "${CALLS_LOG}"
if [[ "$1" == "-m" && "$2" == "pip" && "$3" == "show" && "$4" == "pip-tools" ]]; then
  exit 1
fi
if [[ "$1" == "./src/scripts/security/generate_supply_chain_artifacts.py" ]]; then
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "${STUB_BIN}/python3"

  cat > "${STUB_BIN}/pip-compile" <<'EOF'
#!/usr/bin/env bash
echo "pip-compile $*" >> "${CALLS_LOG}"
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--output-file" ]]; then
    out="$arg"
    break
  fi
  prev="$arg"
done
if [[ -n "$out" ]]; then
  cat > "$out" <<'OUT'
requests==2.34.2 \
    --hash=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OUT
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/pip-compile"

  run bash -c "cd '${FIXTURE_ROOT}' && \
    export VIRTUAL_ENV=\"\$(cd '${FIXTURE_ROOT}/fixture-venv' && pwd -P)\" && \
    export PATH='${STUB_BIN}:'\${PATH} && \
    export CI=true && \
    ./03_prepare_supply_chain_integrity.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--signing-mode required"* ]]
}
