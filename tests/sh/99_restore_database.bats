#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "99_restore_database.sh"
  mkdir -p "${FIXTURE_ROOT}/backups"
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
  cat > "${STUB_BIN}/shasum" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-a" && "$2" == "256" && "$3" == "-c" ]]; then
  exit 0
fi
if [[ "$1" == "-a" && "$2" == "256" ]]; then
  shift 2
  for path in "$@"; do
    echo "deadbeef  ${path}"
  done
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/shasum"
}

teardown() {
  teardown_shell_test
}

stub_managed_profile_helper() {
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
#R090: Stub helper mirrors a managed Supabase profile resolution for restore tests.
profile="default"
while (($#)); do
  case "$1" in
    --profile) shift; profile="${1:-}";;
  esac
  shift
done
if [[ "$profile" == "supabase_direct" ]]; then
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
else
  echo "PROFILE_NAME=supabase"
  echo "DB_DIALECT=postgresql"
  echo "PROFILE_TARGET=managed"
  echo "PG_HOST=aws-0-us-east-1.pooler.supabase.com"
  echo "PG_PORT=5432"
  echo "PG_DBNAME=postgres"
  echo "PG_USER=postgres.ref"
  echo "PG_SSLMODE=require"
  echo "PG_SEARCH_PATH=teller"
  echo "PG_RUNTIME_ROLE="
  echo "PG_ONEPSA_ITEM=EGGNEST_SUPABASE"
fi
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

@test "fails when pg_restore is missing" {
  #R001-T01 #R010-T01 #R015-T01
  stub_cmd 1psa "echo pass"
  stub_cmd psql "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_restore is required"* ]]
}

@test "defaults to latest dump and reports completion path" {
  #R005-T01 #R005-T02 #R020-T01 #R020-T02 #R030-T01 #R030-T02 #R035-T01 #R035-T02 #R095-T01
  old="${FIXTURE_ROOT}/backups/prod_20250101_000000.dump"
  new="${FIXTURE_ROOT}/backups/prod_20250102_000000.dump"
  new_globals="${FIXTURE_ROOT}/backups/prod_20250102_000000_globals.sql"
  new_manifest="${FIXTURE_ROOT}/backups/prod_20250102_000000.manifest.sha256"
  touch "$old" "$new" "${FIXTURE_ROOT}/backups/prod_20250102_000000_globals.sql"
  touch -t 202501010000 "$old"
  touch -t 202501020000 "$new"
  (
    cd "${FIXTURE_ROOT}/backups" && \
      shasum -a 256 "$(basename "$new")" "$(basename "$new_globals")" > "$(basename "$new_manifest")"
  )

  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo ""
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_restore "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restore complete from: ${new}"* ]]
}

@test "table-scoped restore skips globals file requirement" {
  #R040-T01 #R040-T02 #R045-T01 #R050-T01 #R050-T02 #R055-T01 #R060-T01 #R060-T02 #R065-T01 #R101-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  touch "$dump_path"
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  cat > "${STUB_BIN}/pg_restore" <<EOF
#!/usr/bin/env bash
echo pg_restore "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_restore"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path" --table teller.transaction
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"--schema teller --table transaction"* ]]
}

@test "scoped repair SQL uses resolved schema and table identifiers" {
  #R101-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  touch "$dump_path"
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"information_schema.columns"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_restore "exit 0"
  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path" --table teller.transaction
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"columns.table_schema = 'teller'"* ]]
  [[ "$calls" == *"columns.table_name = 'transaction'"* ]]
}

@test "rejects invalid DATABASE_NAME before restore checks" {
  #R100-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  manifest_path="${FIXTURE_ROOT}/backups/snapshot.manifest.sha256"
  touch "$dump_path" "$globals_path"
  (
    cd "${FIXTURE_ROOT}/backups" && \
      shasum -a 256 "$(basename "$dump_path")" "$(basename "$globals_path")" > "$(basename "$manifest_path")"
  )
  stub_cmd 1psa "echo pass"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"
  run env DATABASE_NAME="bad-name!" bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DATABASE_NAME is not a valid PostgreSQL identifier"* ]]
}

@test "rejects malformed table identifier before scoped restore" {
  #R101-T02
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  touch "$dump_path"
  stub_cmd 1psa "echo pass"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"
  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path" --table "teller.bad-table!"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid table identifier supplied to --table"* ]]
}

@test "full restore fails when manifest is missing" {
  #R102-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  touch "$dump_path" "$globals_path"
  stub_cmd 1psa "echo pass"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"
  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Backup integrity manifest is missing"* ]]
}

@test "full restore fails when manifest checksum verification fails" {
  #R102-T02
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  manifest_path="${FIXTURE_ROOT}/backups/snapshot.manifest.sha256"
  touch "$dump_path" "$globals_path" "$manifest_path"
  cat > "${STUB_BIN}/shasum" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-a" && "$2" == "256" && "$3" == "-c" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/shasum"
  stub_cmd 1psa "echo pass"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"
  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Backup integrity check failed"* ]]
}

@test "refuses full restore when teller schema already exists" {
  #R025-T01 #R025-T02
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  manifest_path="${FIXTURE_ROOT}/backups/snapshot.manifest.sha256"
  touch "$dump_path" "$globals_path"
  (
    cd "${FIXTURE_ROOT}/backups" && \
      shasum -a 256 "$(basename "$dump_path")" "$(basename "$globals_path")" > "$(basename "$manifest_path")"
  )
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo "1"
elif [[ "$*" == *"schema_name='teller'"* ]]; then
  echo "1"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  stub_cmd pg_restore "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Schema teller already exists"* ]]
}

@test "fails when teller password lookup is empty" {
  #R070-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  manifest_path="${FIXTURE_ROOT}/backups/snapshot.manifest.sha256"
  touch "$dump_path" "$globals_path"
  (
    cd "${FIXTURE_ROOT}/backups" && \
      shasum -a 256 "$(basename "$dump_path")" "$(basename "$globals_path")" > "$(basename "$manifest_path")"
  )
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"localhost_postgres_teller"* ]]; then
  echo ""
else
  echo "postgres-pass"
fi
EOF
  chmod +x "${STUB_BIN}/1psa"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to read teller password"* ]]
}

@test "full restore re-syncs teller password and verifies teller auth" {
  #R075-T01 #R080-T01 #R085-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  manifest_path="${FIXTURE_ROOT}/backups/snapshot.manifest.sha256"
  touch "$dump_path" "$globals_path"
  (
    cd "${FIXTURE_ROOT}/backups" && \
      shasum -a 256 "$(basename "$dump_path")" "$(basename "$globals_path")" > "$(basename "$manifest_path")"
  )
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"localhost_postgres_teller"* ]]; then
  echo "teller-pass"
else
  echo "postgres-pass"
fi
EOF
  chmod +x "${STUB_BIN}/1psa"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo psql "\$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database"* ]]; then
  echo ""
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  cat > "${STUB_BIN}/pg_restore" <<EOF
#!/usr/bin/env bash
echo pg_restore "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_restore"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"ALTER USER teller WITH PASSWORD"* ]]
  [[ "$calls" == *"-U teller -d prod -tAc SELECT 1;"* ]]
}

@test "managed target refuses full restore" {
  #R090-T01
  stub_managed_profile_helper
  dump_path="${FIXTURE_ROOT}/backups/managed-snapshot.dump"
  touch "$dump_path"
  stub_cmd 1psa "echo managed-pass"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing full restore against managed target"* ]]
  [[ "$output" == *"--table schema.table_name"* ]]
}

@test "managed target table-scoped restore uses profile credentials" {
  #R090-T02 #R090-T03
  stub_managed_profile_helper
  dump_path="${FIXTURE_ROOT}/backups/managed-snapshot.dump"
  touch "$dump_path"
  stub_cmd 1psa "echo managed-pass"
  stub_cmd psql "exit 0"
  cat > "${STUB_BIN}/pg_restore" <<EOF
#!/usr/bin/env bash
echo pg_restore "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_restore"

  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path" --table teller.transaction
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restore complete from: ${dump_path}"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"-h db.example.supabase.co"* ]]
  [[ "$calls" == *"-U postgres.ref"* ]]
  [[ "$calls" == *"-d postgres"* ]]
  [[ "$calls" == *"--schema teller --table transaction"* ]]
}

@test "sqlite profile restore recreates sqlite artifact from backup copy" {
  #R086-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<EOF
#!/usr/bin/env bash
echo "DB_DIALECT=sqlite"
echo "PROFILE_NAME=sqlite"
echo "PROFILE_TARGET=sqlite"
echo "SQLITE_PATH=${FIXTURE_ROOT}/sqlite-dev.db"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  dump_path="${FIXTURE_ROOT}/backups/sqlite_snapshot.dump"
  printf 'sqlite-bytes' > "$dump_path"
  stub_cmd 1psa "echo pass"
  stub_cmd psql "exit 0"
  stub_cmd pg_restore "exit 0"
  run bash "${FIXTURE_ROOT}/99_restore_database.sh" --from "$dump_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restore complete from: ${dump_path}"* ]]
  run bash -c "cmp '${dump_path}' '${FIXTURE_ROOT}/sqlite-dev.db'"
  [ "$status" -eq 0 ]
}
