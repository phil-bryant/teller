#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "98_destroy_database.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "DB_DIALECT=postgresql"
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
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

teardown() {
  teardown_shell_test
}

stub_managed_profile_helper() {
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=supabase_direct"
echo "DB_DIALECT=postgresql"
echo "PROFILE_TARGET=managed"
echo "PG_HOST=db.example.supabase.co"
echo "PG_PORT=5432"
echo "PG_DBNAME=postgres"
echo "PG_USER=postgres.ref"
echo "PG_SSLMODE=require"
echo "PG_SEARCH_PATH=teller"
echo "PG_RUNTIME_ROLE="
echo "PG_ONEPSA_ITEM=EGGNEST_SUPABASE_DIRECT"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

stub_managed_dns_tools() {
  stub_cmd getent "echo '127.0.0.1 localhost'; exit 0"
  stub_cmd host "echo 'localhost has address 127.0.0.1'; exit 0"
}

@test "fails clearly when 1psa is missing" {
  #R001-T01 #R005-T01
  run bash "${FIXTURE_ROOT}/98_destroy_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "wrong confirmation cancels before teardown commands" {
  #R010-T01
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"

  run bash -c "printf 'nope\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Destruction cancelled"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" != *"psql "* ]]
}

@test "successful confirmation runs cleanup and prints completion" {
  #R015-T01 #R020-T01 #R025-T01 #R031-T01 #R031-T02
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"

  run bash -c "printf 'destroy\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleanup complete!"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"DROP DATABASE IF EXISTS prod;"* ]]
  [[ "$calls" == *"prod"* ]]
  [[ "$calls" == *"SELECT 1 FROM pg_database WHERE datname = 'prod';"* ]]
}

@test "rejects invalid local database identifier before teardown SQL" {
  #R030-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "DB_DIALECT=postgresql"
echo "PROFILE_TARGET=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=bad-name!"
echo "PG_USER=teller"
echo "PG_SSLMODE=disable"
echo "PG_SEARCH_PATH=teller"
echo "PG_RUNTIME_ROLE=teller_write"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  stub_cmd 1psa "echo pass"
  run bash "${FIXTURE_ROOT}/98_destroy_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid database identifier"* ]]
}

@test "managed destroy rejects invalid schema identifier before DROP" {
  #R032-T01
  stub_managed_profile_helper
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=supabase_direct"
echo "DB_DIALECT=postgresql"
echo "PROFILE_TARGET=managed"
echo "PG_HOST=db.example.supabase.co"
echo "PG_PORT=5432"
echo "PG_DBNAME=postgres"
echo "PG_USER=postgres.ref"
echo "PG_SSLMODE=require"
echo "PG_SEARCH_PATH=bad-schema!"
echo "PG_RUNTIME_ROLE="
echo "PG_ONEPSA_ITEM=EGGNEST_SUPABASE_DIRECT"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  stub_cmd 1psa "echo pass"
  stub_managed_dns_tools
  stub_cmd psql "exit 0"
  run bash -c "printf 'destroy\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid schema identifier"* ]]
}

@test "managed destroy drops schema safely" {
  #R033-T01
  stub_managed_profile_helper
  stub_cmd 1psa "echo pass"
  stub_managed_dns_tools
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1;"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  run bash -c "printf 'destroy\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"DROP SCHEMA IF EXISTS \"teller\" CASCADE;"* ]]
}

@test "sqlite profile destroy removes sqlite database file" {
  #R026-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<EOF
#!/usr/bin/env bash
echo "DB_DIALECT=sqlite"
echo "PROFILE_NAME=sqlite"
echo "PROFILE_TARGET=sqlite"
echo "SQLITE_PATH=${FIXTURE_ROOT}/sqlite-dev.db"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  touch "${FIXTURE_ROOT}/sqlite-dev.db"
  stub_cmd 1psa "echo pass"
  run bash -c "printf 'destroy\n' | '${FIXTURE_ROOT}/98_destroy_database.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleanup complete!"* ]]
  [ ! -f "${FIXTURE_ROOT}/sqlite-dev.db" ]
}
