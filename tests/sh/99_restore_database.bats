#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "99_restore_database.sh"
  mkdir -p "${FIXTURE_ROOT}/backups"
}

teardown() {
  teardown_shell_test
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
  #R005-T01 #R005-T02 #R020-T01 #R020-T02 #R030-T01 #R030-T02 #R035-T01 #R035-T02
  old="${FIXTURE_ROOT}/backups/prod_20250101_000000.dump"
  new="${FIXTURE_ROOT}/backups/prod_20250102_000000.dump"
  touch "$old" "$new" "${FIXTURE_ROOT}/backups/prod_20250102_000000_globals.sql"
  touch -t 202501010000 "$old"
  touch -t 202501020000 "$new"

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
  #R040-T01 #R040-T02 #R045-T01 #R050-T01 #R050-T02 #R055-T01 #R060-T01 #R060-T02 #R065-T01
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

@test "refuses full restore when teller schema already exists" {
  #R025-T01 #R025-T02
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  touch "$dump_path" "$globals_path"
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
  touch "$dump_path" "$globals_path"
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
  #R075-T01 #R080-T01
  dump_path="${FIXTURE_ROOT}/backups/snapshot.dump"
  globals_path="${FIXTURE_ROOT}/backups/snapshot_globals.sql"
  touch "$dump_path" "$globals_path"
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
