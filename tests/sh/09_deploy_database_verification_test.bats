#!/usr/bin/env bats

# Requirement test-case tags for requirements/09_deploy_database_verification_test-requirements.md

# Traceability numbered tags for requirements/09_deploy_database_verification_test-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R040-T01: Traceability anchor.
# #R045-T01: Traceability anchor.
# #R050-T01: Traceability anchor.
# #R055-T01: Traceability anchor.
# #R060-T01: Traceability anchor.
# #R060-T02: Traceability anchor.
# #R065-T01: Traceability anchor.

load "helpers/common.bash"

make_psql_happy() {
  cat > "${STUB_BIN}/psql" <<'PY'
#!/usr/bin/env python3
import os
import sys

def log_line():
  path = os.environ.get("PSQL_LOG", "")
  if not path:
    return
  with open(path, "a", encoding="utf-8") as h:
    h.write("psql " + " ".join(sys.argv[1:]) + "\n")

def get_sql(a):
  if not a:
    return ""
  tail = a[-1]
  if any(k in tail for k in ("SELECT", "WITH", "select", "with")) or "teller" in tail:
    return tail
  if "-Atc" in a:
    return a[a.index("-Atc") + 1]
  if "-c" in a:
    return a[a.index("-c") + 1]
  return tail

def main():
  log_line()
  args = sys.argv[1:]
  sql = get_sql(args)
  if "teller_read" in sql and "WITH expected" in sql and "role_name" in sql:
    print("", end="")
    return
  if "nspname = 'teller'" in sql and "EXISTS" in sql and "pg_namespace" in sql and "pg_constraint" not in sql:
    print("t", end="")
    return
  if "expected(table_name)" in sql and "institution" in sql and "teller" in sql:
    print("", end="")
    return
  if "transaction_info_view" in sql and "views" in sql and "EXISTS" in sql:
    print("t", end="")
    return
  if "transaction_info_view" in sql and "SELECT 1" in sql and "FROM teller" in sql:
    print("1", end="")
    return
  if "confdeltype" in sql and "transaction_nys_snw_category" in sql:
    if os.environ.get("FK_BROKEN") == "1":
      print("f", end="")
    else:
      print("t", end="")
    return
  if "update_updated_at" in sql and "pg_proc" in sql and "teller" in sql and "EXISTS" in sql and "information_schema.columns" not in sql:
    print("t", end="")
    return
  if "pg_trigger" in sql and "transaction_nys_snw_category" in sql and "update_updated_at" in sql:
    print("t", end="")
    return
  if "information_schema.columns" in sql and "LEFT JOIN actual" in sql and "update_updated_at" in sql:
    if os.environ.get("TRIGGER_GAPS") == "1":
      print("transaction")
    else:
      print("", end="")
    return
  if "pg_stat_ssl" in sql and "pg_backend_pid" in sql:
    if os.environ.get("SSL_INACTIVE") == "1":
      print("f", end="")
    else:
      print("t", end="")
    return
  print("t", end="")

if __name__ == "__main__":
  main()
PY
  chmod +x "${STUB_BIN}/psql"
}

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "09_deploy_database_verification_test.sh"
  export PSQL_LOG="${TEST_TMPDIR}/psql.log"
  : > "${PSQL_LOG}"
  make_psql_happy
  stub_cmd 1psa "echo from1psa"
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
  export PSQL_LOG
}

teardown() {
  teardown_shell_test
}

@test "fails on first psql error" {
  #R001
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_BIN}/psql"
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -ne 0 ]
}

@test "psql command includes custom host and port from env" {
  #R005
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_HOST=custom.local TELLER_DB_PORT=15432 TELLER_DB_PASSWORD=pw TELLER_DB_NAME=d TELLER_DB_USER=u \
    zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -eq 0 ]
  grep -F "custom.local" "${PSQL_LOG}"
  grep -F "15432" "${PSQL_LOG}"
}

@test "uses 1psa when teller db password is unset" {
  #R010
  : > "${PSQL_LOG}"
  make_psql_happy
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -eq 0 ]
  [[ "$(cat "${PSQL_LOG}")" == *"psql "* ]]
}

@test "fails with clear error when database password is empty" {
  #R015
  : > "${PSQL_LOG}"
  make_psql_happy
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
echo ""
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL:"* ]]
}

@test "fails when classification FK is missing ON DELETE CASCADE" {
  #R020 #R025
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw FK_BROKEN=1 zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL:"* ]]
  [[ "$output" == *"CASCADE"* || "$output" == *"cascade"* ]]
}

@test "emits a single pass line for successful verification" {
  #R030 #R035 #R040 #R045
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}

@test "fails when updated_at coverage has gaps" {
  #R040 #R045
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw TRIGGER_GAPS=1 zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing updated_at trigger coverage: transaction"* ]]
  [[ "$output" == *"❌ FAIL:"* ]]
}

stub_managed_verify_helper() {
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=supabase"
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

@test "managed profile skips role existence check" {
  #R050
  : > "${PSQL_LOG}"
  make_psql_happy
  stub_managed_verify_helper
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -eq 0 ]
  ! grep -F "WITH expected(role_name)" "${PSQL_LOG}"
}

@test "uses profile psa item when password env is unset" {
  #R055
  : > "${PSQL_LOG}"
  make_psql_happy
  stub_managed_verify_helper
  : > "${TEST_TMPDIR}/1psa.log"
  cat > "${STUB_BIN}/1psa" <<EOF
#!/usr/bin/env bash
echo "1psa \$*" >> "${TEST_TMPDIR}/1psa.log"
echo "from1psa"
EOF
  chmod +x "${STUB_BIN}/1psa"
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -eq 0 ]
  grep -F "1psa -p eggnest_supabase" "${TEST_TMPDIR}/1psa.log"
}

stub_require_ssl_helper() {
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "PROFILE_NAME=local"
echo "PROFILE_TARGET=local"
echo "PG_HOST=localhost"
echo "PG_PORT=5432"
echo "PG_DBNAME=prod"
echo "PG_USER=teller"
echo "PG_SSLMODE=require"
echo "PG_SEARCH_PATH=teller"
echo "PG_RUNTIME_ROLE=teller_write"
echo "PG_ONEPSA_ITEM=localhost_postgres_teller"
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
}

@test "ssl-required deploy fails when pg_stat_ssl reports unencrypted session" {
  #R060
  : > "${PSQL_LOG}"
  make_psql_happy
  stub_require_ssl_helper
  run env TELLER_DB_PASSWORD=pw SSL_INACTIVE=1 zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sslmode=require"* ]]
  [[ "$output" == *"pg_stat_ssl"* ]]
}

@test "ssl probe is skipped when sslmode is disable" {
  #R060
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -eq 0 ]
  ! grep -F "pg_stat_ssl" "${PSQL_LOG}"
}

@test "fails with setup guidance when db profile file is missing" {
  #R065
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
echo "No DB profile file found. Create one with: cp config/db-profiles-EXAMPLE.json config/db-profiles.json" >&2
exit 1
EOF
  chmod +x "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh"
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/09_deploy_database_verification_test.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cp config/db-profiles-EXAMPLE.json config/db-profiles.json"* ]]
}
