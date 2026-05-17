#!/usr/bin/env bats

# Requirement test-case tags for requirements/08_verify_deploy_database-requirements.md
# #R035-T02: Traceability anchor.

# Traceability numbered tags for requirements/08_verify_deploy_database-requirements.md
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
  print("t", end="")

if __name__ == "__main__":
  main()
PY
  chmod +x "${STUB_BIN}/psql"
}

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "08_verify_deploy_database.sh"
  export PSQL_LOG="${TEST_TMPDIR}/psql.log"
  : > "${PSQL_LOG}"
  make_psql_happy
  stub_cmd 1psa "echo from1psa"
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
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
}

@test "psql command includes custom host and port from env" {
  #R005
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_HOST=custom.local TELLER_DB_PORT=15432 TELLER_DB_PASSWORD=pw TELLER_DB_NAME=d TELLER_DB_USER=u \
    zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
  [ "$status" -eq 0 ]
  grep -F "custom.local" "${PSQL_LOG}"
  grep -F "15432" "${PSQL_LOG}"
}

@test "uses 1psa when teller db password is unset" {
  #R010
  : > "${PSQL_LOG}"
  make_psql_happy
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
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
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL:"* ]]
}

@test "fails when classification FK is missing ON DELETE CASCADE" {
  #R020 #R025
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw FK_BROKEN=1 zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL:"* ]]
  [[ "$output" == *"CASCADE"* || "$output" == *"cascade"* ]]
}

@test "emits a single pass line for successful verification" {
  #R030 #R035 #R040 #R045
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "✅ PASS:")" -eq 1 ]
}

@test "fails when updated_at coverage has gaps" {
  #R040 #R045
  : > "${PSQL_LOG}"
  make_psql_happy
  run env TELLER_DB_PASSWORD=pw TRIGGER_GAPS=1 zsh "${FIXTURE_ROOT}/08_verify_deploy_database.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing updated_at trigger coverage: transaction"* ]]
  [[ "$output" == *"❌ FAIL:"* ]]
}
