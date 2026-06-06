#!/usr/bin/env bats
load "helpers/common.bash"

#R001: Prepare bats fixture state for script-level verification tests.
setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/db_profile_export.sh" "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

#R001: Cleanup bats fixture state after script-level verification tests.
teardown() {
  teardown_shell_test
}

@test "prints expected export keys and omits sqlcipher secret" {
  #R001-T01: Verify successful execution prints required export keys with shell-quoted values.
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
DB_DIALECT=postgresql
PROFILE_NAME=local
PROFILE_TARGET=local
PG_HOST=localhost
PG_PORT=5432
PG_DBNAME=prod
PG_USER=teller
PG_SSLMODE=disable
PG_SEARCH_PATH=teller,public
PG_RUNTIME_ROLE=teller_write
PG_ONEPSA_ITEM=localhost_postgres_teller
SQLCIPHER_KEY=''
OUT
EOF
  chmod +x "${STUB_BIN}/python3"

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_DIALECT=postgresql"* ]]
  [[ "$output" == *"PROFILE_NAME=local"* ]]
  [[ "$output" == *"PG_DBNAME=prod"* ]]
  [[ "$output" == *"PG_ONEPSA_ITEM=localhost_postgres_teller"* ]]
  [[ "$output" != *"SQLCIPHER_KEY="* ]]
}

@test "prints sqlite exports without sqlcipher key by default" {
  #R015-T02: Verify sqlite exports omit sqlcipher key unless explicitly requested.
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
DB_DIALECT=sqlite
PROFILE_NAME=sqlite
PROFILE_TARGET=sqlite
SQLITE_PATH=/tmp/teller.sqlite3
SQLCIPHER_KEY='cipher-key'
OUT
EOF
  chmod +x "${STUB_BIN}/python3"

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh --profile sqlite"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_DIALECT=sqlite"* ]]
  [[ "$output" == *"SQLITE_PATH=/tmp/teller.sqlite3"* ]]
  [[ "$output" != *"SQLCIPHER_KEY="* ]]
}

@test "prints sqlcipher key only when explicitly requested" {
  #R015-T01: Verify default output omits SQLCIPHER key exports and explicit key mode returns the key value.
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
printf '%s' "cipher-key"
EOF
  chmod +x "${STUB_BIN}/python3"

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh --print-sqlcipher-key"
  [ "$status" -eq 0 ]
  [ "$output" = "cipher-key" ]
}

@test "supports profile override and rejects unknown args" {
  #R005-T01: Verify profile override is propagated and unknown flags fail with an explicit error.
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=${TELLER_DB_PROFILE:-unset}"
echo "PG_DBNAME=prod"
EOF
  chmod +x "${STUB_BIN}/python3"

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh --profile test-profile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROFILE_NAME=test-profile"* ]]

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh --bad-flag"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg"* ]]
}

@test "fails clearly when profile resolver errors" {
  #R010-T01: Simulate profile-resolution failure and verify stderr guidance plus failing exit status.
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
echo "profile resolution failed" >&2
exit 1
EOF
  chmod +x "${STUB_BIN}/python3"

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile resolution failed"* ]]
}
