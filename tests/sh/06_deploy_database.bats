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

setup_06_fixture() {
  create_repo_fixture
  copy_script_to_fixture "06_deploy_database.sh"
  mkdir -p "${FIXTURE_ROOT}/sql/postgres"
  for f in create_database configure_database teller_enums teller_institution \
    teller_account_links teller_account teller_identity teller_identity_name \
    teller_identity_email teller_identity_phone_number teller_identity_address_data \
    teller_identity_address teller_account_identities teller_routing_numbers \
    teller_account_details_links teller_account_details teller_account_balances_links \
    teller_account_balances teller_transaction_type teller_transaction_details_counterparty \
    teller_transaction_links teller_transaction_details teller_transaction \
    teller_nys_snw_category teller_transaction_nys_snw_category create_triggers \
    teller_transaction_info_view create_audit; do
    echo "-- $f" > "${FIXTURE_ROOT}/sql/postgres/${f}.sql"
  done
  stub_cmd 1psa "echo fakesecret"
  export CALLS_LOG
}

teardown() {
  teardown_shell_test
}

setup() {
  setup_shell_test
  setup_06_fixture
  make_psql_stub 0
}

@test "exits non-zero on first psql failure" {
  #R001
  make_psql_stub 1
  run bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -ne 0 ]
}

@test "fails when 1psa is missing" {
  #R005
  : > "${STUB_BIN}/1psa"
  rm -f "${STUB_BIN}/1psa" 2>/dev/null
  #PATH only has STUB_BIN - 1psa removed from stub (use empty stub dir without 1psa)
  # recreate stub path without 1psa
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1psa is required"* ]]
}

@test "all psql invocations include fail-fast on_error_stop" {
  #R006 #R007 #R008
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  stub_cmd 1psa "echo pw"
  run bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -eq 0 ]
  local n_psql
  n_psql="$(grep -c "psql" "${CALLS_LOG}" || true)"
  local n_stop
  n_stop="$(grep -c "ON_ERROR_STOP" "${CALLS_LOG}" || true)"
  [ "$n_psql" -ge 1 ]
  [ "$n_psql" -eq "$n_stop" ]
}

@test "uses configurable 1psa source for admin and teller roles" {
  #R010 #R015
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
    bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F "1psa -p pg_item" "${CALLS_LOG2}"
  grep -F "1psa -p tl_item" "${CALLS_LOG2}"
}

@test "fails when postgres password is empty" {
  #R020
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
echo ""
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to read postgres password"* || "$output" == *"Failed to read teller password"* ]]
}

@test "runs bootstrap and teller SQL in order through sql directory" {
  #R025 #R030 #R035
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep "create_database.sql" "${CALLS_LOG}"
  grep "configure_database.sql" "${CALLS_LOG}"
  grep "teller_account.sql" "${CALLS_LOG}"
  grep "sql/postgres" "${CALLS_LOG}" || grep "\-f" "${CALLS_LOG}"
}

@test "applies create_triggers after classification table and enforces cascade alter" {
  #R040 #R045
  export PATH="${STUB_BIN}:/usr/bin:/bin"
  run bash "${FIXTURE_ROOT}/06_deploy_database.sh"
  [ "$status" -eq 0 ]
  awk '
    /teller_transaction_nys_snw_category/ { t = NR }
    /create_triggers\.sql/ { c = NR }
    END { exit (t > 0 && c > 0 && t < c) ? 0 : 1 }
  ' "${CALLS_LOG}"
  grep "ON DELETE CASCADE" "${CALLS_LOG}"
}
