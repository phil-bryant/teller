#!/usr/bin/env bats
load "helpers/common.bash"

make_psql_stub() {
  local fail_at="${1:-0}"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
i=\$(wc -l < "${TEST_TMPDIR}/psql_n" 2>/dev/null | tr -d ' ')
i=\$((\${i:-0} + 1))
echo "\$i" > "${TEST_TMPDIR}/psql_n"
echo "psql \$*" >> "${CALLS_LOG}"
if [ "${fail_at}" != "0" ] && [ "\$i" = "${fail_at}" ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  : > "${TEST_TMPDIR}/psql_n" 2>/dev/null || true
  : > "${CALLS_LOG}"
}

setup_07_fixture() {
  create_repo_fixture
  copy_script_to_fixture "05_deploy_database.sh"
  mkdir -p "${FIXTURE_ROOT}/src/sql/postgres"
  for f in create_database configure_database teller_enums teller_institution \
    teller_account_links teller_account teller_identity teller_identity_name \
    teller_identity_email teller_identity_phone_number teller_identity_address_data \
    teller_identity_address teller_account_identities teller_routing_numbers \
    teller_account_details_links teller_account_details teller_account_balances_links \
    teller_account_balances teller_transaction_type teller_transaction_details_counterparty \
    teller_transaction_links teller_transaction_details teller_transaction \
    teller_nys_snw_category teller_transaction_nys_snw_category \
    teller_transaction_email_match_run teller_transaction_email_candidate \
    teller_transaction_email_match teller_transaction_email_match_audit create_triggers \
    teller_transaction_info_view create_audit grant_ingest_reconcile_privileges; do
    echo "-- $f" > "${FIXTURE_ROOT}/src/sql/postgres/${f}.sql"
  done
  stub_cmd 1psa "echo fakesecret"
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
  export CALLS_LOG
}

teardown() {
  teardown_shell_test
}

setup() {
  setup_shell_test
  setup_07_fixture
  make_psql_stub 0
}

@test "exits non-zero on first psql failure" {
  #R001-T01
  make_psql_stub 1
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is missing" {
  #R005-T01
  : > "${STUB_BIN}/1psa"
  rm -f "${STUB_BIN}/1psa" 2>/dev/null
  #PATH only has STUB_BIN - 1psa removed from stub (use empty stub dir without 1psa)
  # recreate stub path without 1psa
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "all psql invocations include fail-fast on_error_stop" {
  #R006-T01 #R007-T01 #R008-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  stub_cmd 1psa "echo pw"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  local n_psql
  n_psql="$(grep -c "psql" "${CALLS_LOG}" || true)"
  local n_stop
  n_stop="$(grep -c "ON_ERROR_STOP" "${CALLS_LOG}" || true)"
  [ "$n_psql" -ge 1 ]
  [ "$n_psql" -eq "$n_stop" ]
}

@test "uses configurable 1psa source for admin and teller roles" {
  #R010-T01 #R015-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  : > "${CALLS_LOG}"
  cat > "${STUB_BIN}/1psa" <<EOF
#!/usr/bin/env bash
echo "1psa \$*" >> "${CALLS_LOG2:-${TEST_TMPDIR}/1psa.log}"
echo "pw"
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
  export CALLS_LOG2="${TEST_TMPDIR}/1psa.log"
  : > "${CALLS_LOG2}"
  run env POSTGRES_PSA_ITEM=pg_item TELLER_PSA_ITEM=tl_item \
    bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F "1psa -p pg_item" "${CALLS_LOG2}"
  grep -F "1psa -p tl_item" "${CALLS_LOG2}"
}

@test "fails when postgres password is empty" {
  #R020-T01
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
echo ""
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to read postgres password"* || "$output" == *"Failed to read teller password"* ]]
}

@test "runs bootstrap and teller SQL in order through sql directory" {
  #R025-T01 #R030-T01 #R035-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep "create_database.sql" "${CALLS_LOG}"
  grep "configure_database.sql" "${CALLS_LOG}"
  grep "teller_account.sql" "${CALLS_LOG}"
  grep "sql/postgres" "${CALLS_LOG}" || grep "\-f" "${CALLS_LOG}"
}

@test "applies create_triggers after classification table and enforces cascade alter" {
  #R040-T01 #R045-T01 #R045-T02
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  awk '
    /teller_transaction_nys_snw_category/ { t = NR }
    /create_triggers\.sql/ { c = NR }
    END { exit (t > 0 && c > 0 && t < c) ? 0 : 1 }
  ' "${CALLS_LOG}"
  grep "ON DELETE CASCADE" "${CALLS_LOG}"
}

@test "ensures pgtap extension is created in prod during bootstrap" {
  #R050-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep "CREATE EXTENSION IF NOT EXISTS pgtap" "${CALLS_LOG}"
}

@test "applies explicit ingest reconcile grants after audit setup" {
  #R055-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  awk '
    /create_audit\.sql/ { a = NR }
    /grant_ingest_reconcile_privileges\.sql/ { g = NR }
    END { exit (a > 0 && g > 0 && a < g) ? 0 : 1 }
  ' "${CALLS_LOG}"
}

stub_managed_profile_helper() {
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=supabase_direct"
echo "PROFILE_TARGET=managed"
echo "PG_HOST=db.example.supabase.co"
echo "PG_PORT=5432"
echo "PG_DBNAME=postgres"
echo "PG_USER=postgres"
echo "PG_SSLMODE=require"
echo "PG_SEARCH_PATH=teller"
echo "PG_RUNTIME_ROLE=''"
echo "PG_ONEPSA_ITEM=eggnest_supabase"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

@test "managed profile drives deploy through profile helper" {
  #R060-T01 #R070-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  stub_managed_profile_helper
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F "db.example.supabase.co" "${CALLS_LOG}"
  grep -F "teller_account.sql" "${CALLS_LOG}"
}

@test "managed deploy skips bootstrap pgtap and ingest grant SQL" {
  #R065-T01 #R075-T01 #R080-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  stub_managed_profile_helper
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  ! grep "create_database.sql" "${CALLS_LOG}"
  ! grep "configure_database.sql" "${CALLS_LOG}"
  ! grep "CREATE EXTENSION IF NOT EXISTS pgtap" "${CALLS_LOG}"
  ! grep "grant_ingest_reconcile_privileges.sql" "${CALLS_LOG}"
}

@test "local deploy is idempotent when prod database already exists" {
  #R085-T01 #R096-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  cat > "${STUB_BIN}/psql" <<EOF
#!/usr/bin/env bash
echo "psql \$*" >> "${CALLS_LOG}"
if [[ "\$*" == *"SELECT 1 FROM pg_database WHERE datname = :'db_name'"* ]]; then
  echo "1"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/psql"
  : > "${CALLS_LOG}"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  ! grep -F "create_database.sql" "${CALLS_LOG}"
  grep -F "configure_database.sql" "${CALLS_LOG}"
  grep -F -- "-v db_name=prod" "${CALLS_LOG}"
}

@test "rejects invalid PG_DBNAME before deploy SQL" {
  #R095-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
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
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PG_DBNAME is not a valid PostgreSQL identifier"* ]]
}

@test "rejects invalid PG_USER before deploy SQL" {
  #R095-T02
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PROFILE_TARGET=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=bad-user!"
echo "PG_SSLMODE=disable"
echo "PG_SEARCH_PATH=teller"
echo "PG_RUNTIME_ROLE=teller_write"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PG_USER is not a valid PostgreSQL identifier"* ]]
}

@test "fails with setup guidance when db profile file is missing" {
  #R090-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "No DB profile file found. Create one with: cp config/db-profiles-EXAMPLE.json config/db-profiles.json" >&2
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cp config/db-profiles-EXAMPLE.json config/db-profiles.json"* ]]
}

@test "sqlite profile deploy applies sqlite ddl without postgres bootstrap" {
  #R071-T01
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  mkdir -p "${FIXTURE_ROOT}/src/sql/sqlite"
  echo "-- sqlite schema" > "${FIXTURE_ROOT}/src/sql/sqlite/create_database.sql"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "DB_DIALECT=sqlite"
echo "PROFILE_NAME=sqlite"
echo "PROFILE_TARGET=sqlite"
echo "SQLITE_PATH=/tmp/teller.sqlite3"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  cat > "${STUB_BIN}/sqlite3" <<EOF
#!/usr/bin/env bash
echo "sqlite3 \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/sqlite3"
  run bash "${FIXTURE_ROOT}/05_deploy_database.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"sqlite3 "* ]]
  [[ "$calls" != *"psql "* ]]
}
