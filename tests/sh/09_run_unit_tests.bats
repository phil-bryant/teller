#!/usr/bin/env bats

# Requirement test-case tags for requirements/09_run_unit_tests-requirements.md
# #R020-T02: Traceability anchor.
# #R020-T03: Traceability anchor.
# #R025-T02: Traceability anchor.
# #R025-T03: Traceability anchor.
# #R025-T04: Traceability anchor.
# #R025-T05: Traceability anchor.
# #R025-T06: Traceability anchor.
# #R025-T07: Traceability anchor.
# #R025-T08: Traceability anchor.
# #R025-T09: Traceability anchor.
# #R035-T01: Traceability anchor.

# Traceability numbered tags for requirements/09_run_unit_tests-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "09_run_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/scripts"
  cat > "${FIXTURE_ROOT}/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PROFILE_TARGET=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_SEARCH_PATH=teller"
echo "PG_RUNTIME_ROLE=teller_write"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/scripts/db_profile_export.sh"
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

  run bash -c "cd '${TEST_TMPDIR}' && RUN_SHELL_TESTS=false RUN_SWIFT_TESTS=false '${FIXTURE_ROOT}/09_run_unit_tests.sh'"
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

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
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

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=true RUN_PYTHON_TESTS=false RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "runs sql suite by default when sql tests are present" {
  #R025
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

  run bash -c "cd '${FIXTURE_ROOT}' && TELLER_DB_PASSWORD=pw ./09_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "fails with actionable message when sql tests are enabled but pg_prove is missing" {
  #R025
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

  run bash -c "cd '${FIXTURE_ROOT}' && TELLER_DB_PASSWORD=pw RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_prove is required for pgTAP SQL unit tests"* ]]
}

@test "uses user-local pg_prove from ~/perl5/bin when PATH lacks pg_prove" {
  #R025
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
  mkdir -p "${HOME}/perl5/bin"
  cat > "${HOME}/perl5/bin/pg_prove" <<EOF
#!/usr/bin/env bash
echo "pg_prove_home \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${HOME}/perl5/bin/pg_prove"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && TELLER_DB_PASSWORD=pw RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"pg_prove_home --dbname prod ./tests/sql/smoke.sql"* ]]
}

@test "fails clearly when sql preflight cannot query database" {
  #R025
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql: error: connection failed" >&2
exit 2
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_prove "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && TELLER_DB_PASSWORD=pw RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to query 'prod' for pgtap extension availability"* ]]
  [[ "$output" == *"connection failed"* ]]
}

@test "fails with actionable message when pgtap extension is missing" {
  #R025
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

  run bash -c "cd '${FIXTURE_ROOT}' && TELLER_DB_PASSWORD=pw RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pgtap extension is required in database"* ]]
}

@test "uses 1psa fallback when teller db password env is unset" {
  #R025
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  cat > "${STUB_BIN}/1psa" <<EOF
#!/usr/bin/env bash
echo "1psa \$*" >> "${CALLS_LOG}"
echo "pw"
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql \$*" >> "${CALLS_LOG}"
echo "1"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_prove "exit 0"
  mkdir -p "${FIXTURE_ROOT}/tests/sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"1psa -p localhost_postgres_teller"* ]]
}

@test "can disable sql suite via RUN_SQL_TESTS=false" {
  #R025
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

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
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

  run bash -c "cd '${FIXTURE_ROOT}' && ./09_run_unit_tests.sh"
  [ "$status" -eq 0 ]
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

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SWIFT_TESTS=false ./09_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "does not invoke macOS crash reporter verification script" {
  #R030
  run grep -E 'verify_macos_crash_test|CRASH_REPORTER_SMOKE' "${FIXTURE_ROOT}/09_run_unit_tests.sh"
  [ "$status" -ne 0 ]
}

@test "fails sql preflight with setup guidance when db profile file is missing" {
  #R035
  stub_cmd bats "exit 0"
  stub_cmd python3 "exit 0"
  stub_cmd swift "exit 0"
  stub_cmd psql "echo 1; exit 0"
  stub_cmd pg_prove "exit 0"
  cat > "${FIXTURE_ROOT}/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "No DB profile file found. Create one with: cp db-profiles-EXAMPLE.json db-profiles.json" >&2
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/scripts/db_profile_export.sh"
  mkdir -p "${FIXTURE_ROOT}/tests/sql"
  cat > "${FIXTURE_ROOT}/tests/sql/smoke.sql" <<'EOF'
SELECT 1;
EOF

  run bash -c "cd '${FIXTURE_ROOT}' && RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SWIFT_TESTS=false RUN_SQL_TESTS=true ./09_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cp db-profiles-EXAMPLE.json db-profiles.json"* ]]
}
