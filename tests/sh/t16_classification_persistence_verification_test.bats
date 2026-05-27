#!/usr/bin/env bats
load "helpers/common.bash"

write_psql16() {
  cat > "${STUB_BIN}/psql" <<'PY'
#!/usr/bin/env python3
import os, sys, re
a = sys.argv[1:]
logp = os.environ.get("PSQL_16", "")
if logp:
    with open(logp, "a", encoding="utf-8") as f:
        f.write("psql " + " ".join(a) + "\n")
sql = a[-1] if a else ""
if "FROM teller.transaction" in sql and "status = 'posted'" in sql and "nys_snw" not in sql:
    print("txn1", end="")
    raise SystemExit(0)
if "FROM teller.nys_snw_category" in sql and "nys_snw_category_id" in sql and "ORDER" in sql:
    print("7", end="")
    raise SystemExit(0)
if "transaction_nys_snw_category" in sql and "nys_snw_category_id" in sql and "type" in sql:
    print("txn1:7:user", end="")
    raise SystemExit(0)
print("", end="")
PY
  chmod +x "${STUB_BIN}/psql"
}

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "t16_classification_persistence_verification_test.sh"
  export PSQL_16="${TEST_TMPDIR}/ps16.log"
  : > "${PSQL_16}"
  export CURL_LOG16="${TEST_TMPDIR}/curl16.log"
  : > "${CURL_LOG16}"
  write_psql16
  cat > "${STUB_BIN}/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "\${CURL_LOG16}"
printf '%s' '{"ok": true}'
exit 0
EOF
  chmod +x "${STUB_BIN}/curl"
  stub_cmd 1psa "echo dbpass"
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
  export PATH="${STUB_BIN}:/usr/bin:/bin"
}

teardown() {
  teardown_shell_test
}

@test "fails on psql error" {
  #R001-T01
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_BIN}/psql"
  run env TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 \
    zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -ne 0 ]
}

@test "auto-resolves posted transaction and category" {
  #R005-T01 #R005-T02 #R005-T03
  : > "${PSQL_16}"; : > "${CURL_LOG16}"
  write_psql16
  run env -u TXN_ID -u CATEGORY_ID TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ PASS:"* ]]
}

@test "strict mode requires category id" {
  #R006-T01 #R006-T02
  run env -u CATEGORY_ID TELLER_DB_PASSWORD=pw TXN_ID=txn1 \
    zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -ne 0 ]
}

@test "sends request to https api url and database host from env" {
  #R010-T01
  : > "${PSQL_16}"; : > "${CURL_LOG16}"
  write_psql16
  run env TELLER_CLASSIFIER_API_URL="https://h.example:12" TELLER_DB_HOST=fromenv TELLER_DB_PORT=33 \
    TELLER_DB_USER=u TELLER_DB_NAME=prod TELLER_DB_PASSWORD=sec TXN_ID=txn1 CATEGORY_ID=7 \
    zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -eq 0 ]
  grep "h.example:12" "${CURL_LOG16}"
  grep "fromenv" "${PSQL_16}"
}

@test "rejects http api url override" {
  run env TELLER_CLASSIFIER_API_URL="http://h.example:12" TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 \
    zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -ne 0 ]
  [[ "$output" == *"must use https://"* ]]
}

@test "resolves empty password with 1psa" {
  #R015-T01
  : > "${PSQL_16}"; : > "${CURL_LOG16}"
  write_psql16
  run env -u TELLER_DB_PASSWORD -u TXN_ID -u CATEGORY_ID zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh"
  [ "$status" -eq 0 ]
}

@test "api json uses transaction and category" {
  #R020-T01 #R020-T02 #R035-T01
  : > "${CURL_LOG16}"
  : > "${PSQL_16}"
  write_psql16
  run env TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -eq 0 ]
  grep "txn1" "${CURL_LOG16}"
  grep "7" "${CURL_LOG16}"
  grep "X-Teller-Write-Token" "${CURL_LOG16}"
}

@test "persists line matches expected format" {
  #R025-T01
  : > "${CURL_LOG16}"; : > "${PSQL_16}"
  write_psql16
  run env TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -eq 0 ]
  [[ "$output" == *"txn1:7:user"* ]]
}

@test "pass output includes details before status" {
  #R030-T01 #R030-T02 #R030-T03 #R030-T04
  : > "${CURL_LOG16}"; : > "${PSQL_16}"
  write_psql16
  run env TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -eq 0 ]
  [[ "$output" == *"API response:"* ]]
  [[ "$output" == *"Persisted row:"* ]]
  [[ "$output" == *"✅ PASS:"* ]]
}

@test "fails on curl error" {
  cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"/health"* ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/curl"
  write_psql16
  run env CLASSIFICATION_PERSISTENCE_START_API=false TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL:"* ]]
  [[ "$output" == *"classification API request failed"* ]]
}

@test "fails with setup guidance when db profile file is missing" {
  #R040-T01
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "No DB profile file found. Create one with: cp config/db-profiles-EXAMPLE.json config/db-profiles.json" >&2
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  run env TELLER_DB_PASSWORD=pw TXN_ID=txn1 CATEGORY_ID=7 \
    zsh "${FIXTURE_ROOT}/t16_classification_persistence_verification_test.sh" --require-env-ids
  [ "$status" -ne 0 ]
  [[ "$output" == *"cp config/db-profiles-EXAMPLE.json config/db-profiles.json"* ]]
}
