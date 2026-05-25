#!/usr/bin/env bats

# Traceability numbered tags for requirements/98_destroy_database-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "98_destroy_database.sh"
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
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
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

teardown() {
  teardown_shell_test
}

@test "fails clearly when 1psa is missing" {
  #R001 #R005
  run bash "${FIXTURE_ROOT}/98_destroy_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "wrong confirmation cancels before teardown commands" {
  #R010
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
  #R015 #R020 #R025
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
  [[ "$calls" == *"DROP DATABASE IF EXISTS"* ]]
  [[ "$calls" == *"prod"* ]]
}
