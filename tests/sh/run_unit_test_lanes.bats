#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts" "${FIXTURE_ROOT}/src/macos-ui/Tests"
  cp "$(repo_root)/src/scripts/run_unit_test_lanes.sh" "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
}

teardown() {
  teardown_shell_test
}

@test "exports hypothesis storage under artifacts/cache" {
  #R038-T01
  run bash -c "
    # shellcheck disable=SC1091
    source '${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh'
    export_test_cache_env '${FIXTURE_ROOT}'
    printf '%s' \"\${HYPOTHESIS_STORAGE_DIRECTORY}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifacts/cache/hypothesis"* ]]
}

@test "runs from repo root and honors disabled lanes" {
  #R001-T01 #R030-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
echo "PROFILE_TARGET=$(pwd)"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"

  run bash -c "
    cd '${TEST_TMPDIR}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
}

@test "fails fast when db profile helper is missing" {
  #R005-T01 #R015-T01 #R025-T01 #R035-T01
  run bash -c "
    cd '${FIXTURE_ROOT}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"DB profile helper is missing or not executable"* ]]
}

@test "swift lane invokes lock helper and retries stale-cache failure once" {
  #R010-T01 #R020-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"

  cat > "${FIXTURE_ROOT}/src/scripts/macos_ui_swift_lock.sh" <<'EOF'
#!/usr/bin/env bash
macos_ui_with_swiftpm_lock() {
  echo "lock:$1:$2:$3" >> "${CALLS_LOG}"
  shift 3
  "$@"
}
EOF

  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "${CALLS_LOG}"
if [[ "$*" == *"swift test --package-path ./src/macos-ui"* ]]; then
  marker="${TEST_TMPDIR}/swift-first"
  if [[ ! -f "$marker" ]]; then
    touch "$marker"
    echo "cannot be accessed .build/" >&2
    exit 1
  fi
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"

  run bash -c "
    cd '${FIXTURE_ROOT}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=true \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"lock:"* ]]
  [[ "$calls" == *"swift test --package-path ./src/macos-ui"* ]]
}

@test "swift lane skips gracefully when sandbox_apply is denied" {
  #R020-T02
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"

  cat > "${FIXTURE_ROOT}/src/scripts/macos_ui_swift_lock.sh" <<'EOF'
#!/usr/bin/env bash
macos_ui_with_swiftpm_lock() {
  shift 3
  "$@"
}
EOF

  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "sandbox_apply: Operation not permitted" >&2
exit 1
EOF
  chmod +x "${STUB_BIN}/swift"

  run bash -c "
    cd '${FIXTURE_ROOT}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=false RUN_SWIFT_TESTS=true \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
}

@test "strips invalid --cache-dir from inherited PYTEST_ADDOPTS" {
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

@test "python lane survives invalid --cache-dir in PYTEST_ADDOPTS" {
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"

  mkdir -p "${FIXTURE_ROOT}/teller-venv/bin" "${FIXTURE_ROOT}/tests/py"
  cat > "${FIXTURE_ROOT}/tests/py/test_stub.py" <<'EOF'
def test_ok():
    assert True
EOF
  cat > "${FIXTURE_ROOT}/teller-venv/bin/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" ]]; then
  exec /usr/bin/python3 "$@"
fi
if [[ "${1:-}" == "-m" && "${2:-}" == "pytest" ]]; then
  if [[ "${PYTEST_ADDOPTS:-}" == *"--cache-dir="* ]]; then
    echo "invalid pytest addopts: ${PYTEST_ADDOPTS}" >&2
    exit 2
  fi
  echo "pytest ok"
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "${FIXTURE_ROOT}/teller-venv/bin/python3"

  run bash -c "
    cd '${FIXTURE_ROOT}'
    export PYTEST_ADDOPTS='--cache-dir=./artifacts/cache/pytest'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=true RUN_SQL_TESTS=false RUN_SWIFT_TESTS=false \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"pytest ok"* ]]
}

@test "sql lane runs sqlite sql tests when sqlite profile is active" {
  #R005-T01 #R025-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--print-sqlcipher-key" ]]; then
  printf '%s' "cipher-key"
  exit 0
fi
echo "DB_DIALECT=sqlite"
echo "PROFILE_NAME=sqlite"
echo "PROFILE_TARGET=sqlite"
echo "SQLITE_PATH=${FIXTURE_ROOT}/sqlite-dev.db"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  printf 'db' > "${FIXTURE_ROOT}/sqlite-dev.db"
  mkdir -p "${FIXTURE_ROOT}/tests/sql/sqlite"
  cat > "${FIXTURE_ROOT}/tests/sql/sqlite/01_sqlite_smoke.sql" <<'EOF'
SELECT 1;
EOF
  cat > "${STUB_BIN}/sqlcipher" <<EOF
#!/usr/bin/env bash
echo "sqlcipher \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/sqlcipher"
  run bash -c "
    cd '${FIXTURE_ROOT}'
    RUN_SHELL_TESTS=false RUN_PYTHON_TESTS=false RUN_SQL_TESTS=true RUN_SWIFT_TESTS=false \
      '${FIXTURE_ROOT}/src/scripts/run_unit_test_lanes.sh'
  "
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"sqlcipher "* ]]
}
