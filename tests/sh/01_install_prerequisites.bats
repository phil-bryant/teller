#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "01_install_prerequisites.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails clearly when brew is missing" {
  #R001 #R005 #R012
  run bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[Homebrew] Not installed."* ]]
}

@test "idempotent path skips installs when dependencies already exist" {
  #R010 #R035 #R040 #R050 #R079 #R080 #R085 #R090 #R095
  mkdir -p "${TEST_TMPDIR}/pg_install/.git"
  stub_cmd brew "exit 0"
  stub_cmd go "exit 0"
  stub_cmd git "exit 0"
  stub_cmd swiftlint "exit 0"
  stub_cmd bats "exit 0"
  stub_cmd clamscan "exit 0"
  stub_cmd cpanm "exit 0"
  stub_cmd perl "exit 0"
  stub_cmd pg_prove "exit 0"
  stub_cmd 1psa "echo installed; exit 0"

  run bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1psa] Available on PATH"* ]]
  [[ "$output" == *"[pg_install] Repository present"* ]]
}

@test "clones pg_install when missing" {
  #R025 #R030 #R079 #R080 #R085 #R090 #R095
  stub_cmd brew "exit 0"
  stub_cmd go "exit 0"
  stub_cmd swiftlint "exit 0"
  stub_cmd bats "exit 0"
  stub_cmd clamscan "exit 0"
  stub_cmd cpanm "exit 0"
  stub_cmd perl "exit 0"
  stub_cmd pg_prove "exit 0"
  cat > "${STUB_BIN}/git" <<EOF
#!/usr/bin/env bash
echo git "\$*" >> "${CALLS_LOG}"
if [[ "\$1" == "clone" ]]; then
  mkdir -p "\$3/.git"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/git"
  stub_cmd 1psa "echo installed; exit 0"

  run bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[pg_install] Installed"* ]]
}

@test "uses PSA_INSTALL_SUDO_ITEM during install flow" {
  #R015 #R020 #R045 #R065 #R079 #R080 #R085 #R090 #R095
  stub_cmd brew "exit 0"
  stub_cmd go "exit 0"
  stub_cmd swiftlint "exit 0"
  stub_cmd bats "exit 0"
  stub_cmd clamscan "exit 0"
  stub_cmd cpanm "exit 0"
  stub_cmd perl "exit 0"
  stub_cmd pg_prove "exit 0"
  cat > "${STUB_BIN}/git" <<EOF
#!/usr/bin/env bash
echo git "\$*" >> "${CALLS_LOG}"
if [[ "\$1" == "clone" ]]; then
  mkdir -p "\$3/.git" "\$3/bin"
  cat > "\$3/Makefile" <<'MAKE'
all:
	@true
install:
	@true
MAKE
  cat > "\$3/bin/1psa" <<'ONEPSA'
#!/usr/bin/env bash
echo local-1psa "\$*" >> "${CALLS_LOG}"
echo fake-pass
ONEPSA
  chmod +x "\$3/bin/1psa"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/git"
  stub_cmd make '
if [[ "$*" == *"install"* ]]; then
  cat > "'"${STUB_BIN}"'/1psa" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo installed-1psa
EOF
  chmod +x "'"${STUB_BIN}"'/1psa"
fi
exit 0'
  cat > "${STUB_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-S" ]]; then
  shift
fi
"$@"
EOF
  chmod +x "${STUB_BIN}/sudo"

  run env PSA_INSTALL_SUDO_ITEM="custom_item" bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"local-1psa -f custom_item custom_item"* ]]
}

@test "installs bats-core perl and cpanminus when test runners are missing" {
  #R055 #R060 #R070 #R075 #R079 #R080 #R085 #R090 #R095
  mkdir -p "${TEST_TMPDIR}/pg_install/.git"
  stub_cmd go "exit 0"
  stub_cmd git "exit 0"
  stub_cmd swiftlint "exit 0"
  stub_cmd pg_prove "exit 0"
  stub_cmd 1psa "echo installed; exit 0"
  cat > "${STUB_BIN}/brew" <<EOF
#!/usr/bin/env bash
echo brew "\$*" >> "${CALLS_LOG}"
if [[ "\$1" == "install" && "\$2" == "bats-core" ]]; then
  cat > "${STUB_BIN}/bats" <<'BATS'
#!/usr/bin/env bash
exit 0
BATS
  chmod +x "${STUB_BIN}/bats"
fi
if [[ "\$1" == "install" && "\$2" == "cpanminus" ]]; then
  cat > "${STUB_BIN}/cpanm" <<'CPANM'
#!/usr/bin/env bash
exit 0
CPANM
  chmod +x "${STUB_BIN}/cpanm"
fi
if [[ "\$1" == "install" && "\$2" == "perl" ]]; then
  cat > "${STUB_BIN}/perl" <<'PERL'
#!/usr/bin/env bash
exit 0
PERL
  chmod +x "${STUB_BIN}/perl"
fi
if [[ "\$1" == "install" && "\$2" == "clamav" ]]; then
  cat > "${STUB_BIN}/clamscan" <<'CLAMSCAN'
#!/usr/bin/env bash
exit 0
CLAMSCAN
  chmod +x "${STUB_BIN}/clamscan"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"

  run bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"brew install bats-core"* ]]
  [[ "$calls" == *"brew install perl"* ]]
  [[ "$calls" == *"brew install cpanminus"* ]]
  [[ "$calls" == *"brew install clamav"* ]]
}

@test "builds and installs pgtap from theory source when pg_prove is missing" {
  #R085 #R030 #R090 #R079 #R080 #R095
  mkdir -p "${TEST_TMPDIR}/pg_install/.git"
  stub_cmd go "exit 0"
  stub_cmd swiftlint "exit 0"
  stub_cmd bats "exit 0"
  stub_cmd perl "exit 0"
  stub_cmd 1psa "echo installed; exit 0"
  cat > "${STUB_BIN}/git" <<EOF
#!/usr/bin/env bash
echo git "\$*" >> "${CALLS_LOG}"
if [[ "\$1" == "clone" ]]; then
  mkdir -p "\$3/.git"
  cat > "\$3/Makefile" <<'MAKE'
all:
	@true
install:
	@true
MAKE
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/git"
  cat > "${STUB_BIN}/make" <<EOF
#!/usr/bin/env bash
echo make "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/make"
  cat > "${STUB_BIN}/cpanm" <<EOF
#!/usr/bin/env bash
echo cpanm "\$*" >> "${CALLS_LOG}"
mkdir -p "${HOME}/perl5/bin"
cat > "${HOME}/perl5/bin/pg_prove" <<'PGPROVE'
#!/usr/bin/env bash
exit 0
PGPROVE
chmod +x "${HOME}/perl5/bin/pg_prove"
exit 0
EOF
  chmod +x "${STUB_BIN}/cpanm"
  cat > "${STUB_BIN}/brew" <<EOF
#!/usr/bin/env bash
echo brew "\$*" >> "${CALLS_LOG}"
if [[ "\$1" == "install" && "\$2" == "clamav" ]]; then
  cat > "${STUB_BIN}/clamscan" <<'CLAMSCAN'
#!/usr/bin/env bash
exit 0
CLAMSCAN
  chmod +x "${STUB_BIN}/clamscan"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"

  run bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"git clone https://github.com/theory/pgtap.git ${TEST_TMPDIR}/pgtap"* ]]
  [[ "$calls" == *"make -C ${TEST_TMPDIR}/pgtap"* ]]
  [[ "$calls" == *"make -C ${TEST_TMPDIR}/pgtap install"* ]]
  [[ "$calls" == *"cpanm --local-lib=${HOME}/perl5 --reinstall TAP::Parser::SourceHandler::pgTAP"* ]]
  [ -x "${HOME}/perl5/bin/pg_prove" ]
}

@test "installs TAP::Parser::SourceHandler::pgTAP via user-local cpanm" {
  #R090 #R079 #R080 #R095
  mkdir -p "${TEST_TMPDIR}/pg_install/.git"
  mkdir -p "${TEST_TMPDIR}/pgtap/.git"
  cat > "${TEST_TMPDIR}/pgtap/Makefile" <<'MAKE'
all:
	@true
install:
	@true
MAKE
  stub_cmd brew "exit 0"
  stub_cmd go "exit 0"
  stub_cmd git "exit 0"
  stub_cmd swiftlint "exit 0"
  stub_cmd bats "exit 0"
  stub_cmd clamscan "exit 0"
  stub_cmd cpanm "mkdir -p \"${HOME}/perl5/bin\"; printf '#!/usr/bin/env bash\nexit 0\n' > \"${HOME}/perl5/bin/pg_prove\"; chmod +x \"${HOME}/perl5/bin/pg_prove\"; exit 0"
  stub_cmd pg_prove "exit 1"
  stub_cmd 1psa "echo fake-pass; exit 0"
  stub_cmd make "exit 0"
  stub_cmd perl "exit 0"

  run env PSA_INSTALL_SUDO_ITEM="custom_item" bash "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"cpanm --local-lib=${HOME}/perl5 --reinstall TAP::Parser::SourceHandler::pgTAP"* ]]
  [ -x "${HOME}/perl5/bin/pg_prove" ]
}
