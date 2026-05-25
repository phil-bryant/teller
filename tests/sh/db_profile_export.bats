#!/usr/bin/env bats

# Requirement test-case tags for requirements/src/scripts/db_profile_export-requirements.md
# #R001-T01: Verify export key emission.
# #R005-T01: Verify argument handling and profile override behavior.
# #R010-T01: Verify profile-resolution failures propagate clearly.

load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/db_profile_export.sh" "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

teardown() {
  teardown_shell_test
}

@test "prints expected export keys" {
  #R001
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
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
OUT
EOF
  chmod +x "${STUB_BIN}/python3"

  run bash -c "cd '${FIXTURE_ROOT}' && ./src/scripts/db_profile_export.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROFILE_NAME=local"* ]]
  [[ "$output" == *"PG_DBNAME=prod"* ]]
  [[ "$output" == *"PG_ONEPSA_ITEM=localhost_postgres_teller"* ]]
}

@test "supports profile override and rejects unknown args" {
  #R005
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
  #R010
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
