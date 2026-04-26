#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "05_run_unit_tests.sh"
}

teardown() {
  teardown_shell_test
}

@test "runs from repository root regardless of caller cwd" {
  #R001 #R005 #R010
  cat > "${STUB_BIN}/python3" <<EOF
#!/usr/bin/env bash
echo "python3 cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/python3"
  stub_cmd swift "exit 0"
  stub_cmd bats "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${TEST_TMPDIR}' && RUN_SHELL_TESTS=false RUN_SWIFT_TESTS=false '${FIXTURE_ROOT}/05_run_unit_tests.sh'"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"python3 cwd=${FIXTURE_ROOT} args=-m unittest discover tests/py"* ]]
}

@test "fails with actionable message when shell tests are enabled but bats is missing" {
  #R015
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=false ./05_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bats is required"* ]]
}

@test "can disable python suite via RUN_PYTHON_TESTS=false" {
  stub_cmd bats "echo bats-run; exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
echo python-should-not-run
exit 1
EOF
  chmod +x "${STUB_BIN}/python3"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=true RUN_PYTHON_TESTS=false RUN_SWIFT_TESTS=false ./05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "runs sql suite by default when sql tests are present" {
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql \$*" >> "${CALLS_LOG}"
echo "1"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  cat > "${STUB_BIN}/pg_prove" <<EOF
#!/usr/bin/env bash
echo "pg_prove \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_prove"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && ./05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"psql -v ON_ERROR_STOP=1 -d prod -Atqc SELECT 1 FROM pg_extension WHERE extname = 'pgtap' LIMIT 1;"* ]]
  [[ "$calls" == *"pg_prove --dbname prod ./tests/sql/smoke.sql"* ]]
}

@test "fails with actionable message when sql tests are enabled but pg_prove is missing" {
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "1"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./05_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_prove is required for pgTAP SQL unit tests"* ]]
}

@test "fails with actionable message when pgtap extension is missing" {
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_prove "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./05_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pgtap extension is required in database"* ]]
}

@test "can disable sql suite via RUN_SQL_TESTS=false" {
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/pg_prove" <<'EOF'
#!/usr/bin/env bash
echo pg-prove-should-not-run
exit 1
EOF
  chmod +x "${STUB_BIN}/pg_prove"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false ./05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "runs swift suite by default when macos tests exist" {
  #R020
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo "swift \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && ./05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"swift test --package-path ./macos-ui"* ]]
}

@test "can disable swift suite via RUN_SWIFT_TESTS=false" {
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo swift-should-not-run
exit 1
EOF
  chmod +x "${STUB_BIN}/swift"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/macos-ui/Tests"

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SWIFT_TESTS=false ./05_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}
