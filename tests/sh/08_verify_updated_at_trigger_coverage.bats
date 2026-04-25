#!/usr/bin/env bats

load "helpers/common.bash"

write_psql_08() {
  cat > "${STUB_BIN}/psql" <<'PY'
#!/usr/bin/env python3
import os
import sys
args = sys.argv[1:]
if os.environ.get("PSQL_LOG_08"):
  with open(os.environ["PSQL_LOG_08"], "a", encoding="utf-8") as h:
    h.write("psql " + " ".join(args) + "\n")
if not args:
  print(""); raise SystemExit(0)
sql = args[-1]
if "teller" in sql and "updated_at" in sql and "LEFT JOIN" in sql:
  if os.environ.get("GAPS", "") == "1":
    print("teller.someskip")
  else:
    print("")
  raise SystemExit(0)
print("")
PY
  chmod +x "${STUB_BIN}/psql"
}

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "08_verify_updated_at_trigger_coverage.sh"
  export PSQL_LOG_08="${TEST_TMPDIR}/psql08.log"
  : > "${PSQL_LOG_08}"
  write_psql_08
  stub_cmd 1psa "echo p"
  export PATH="${STUB_BIN}:/usr/bin:/bin"
}

teardown() {
  teardown_shell_test
}

@test "fails on psql error" {
  #R001
  cat > "${STUB_BIN}/psql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_BIN}/psql"
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/08_verify_updated_at_trigger_coverage.sh"
  [ "$status" -ne 0 ]
}

@test "psql includes host from teller db env" {
  #R005
  : > "${PSQL_LOG_08}"
  write_psql_08
  run env TELLER_DB_HOST=db.example TELLER_DB_PORT=1234 TELLER_DB_NAME=n TELLER_DB_USER=u TELLER_DB_PASSWORD=pw \
    zsh "${FIXTURE_ROOT}/08_verify_updated_at_trigger_coverage.sh"
  [ "$status" -eq 0 ]
  grep "db.example" "${PSQL_LOG_08}"
}

@test "uses 1psa when teller db password is unset" {
  #R010
  : > "${PSQL_LOG_08}"
  write_psql_08
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/08_verify_updated_at_trigger_coverage.sh"
  [ "$status" -eq 0 ]
}

@test "fails with fail header when database password is empty" {
  #R015
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
printf ''
EOF
  chmod +x "${STUB_BIN}/1psa"
  : > "${PSQL_LOG_08}"
  write_psql_08
  run env -u TELLER_DB_PASSWORD zsh "${FIXTURE_ROOT}/08_verify_updated_at_trigger_coverage.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ FAIL:"* ]]
}

@test "lists missing table when trigger coverage is incomplete" {
  #R020 #R025
  : > "${PSQL_LOG_08}"
  write_psql_08
  run env TELLER_DB_PASSWORD=pw GAPS=1 zsh "${FIXTURE_ROOT}/08_verify_updated_at_trigger_coverage.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"teller.someskip"* ]]
  [[ "$output" == *"❌ FAIL:"* ]]
}

@test "prints pass when all coverage present" {
  #R030
  : > "${PSQL_LOG_08}"
  write_psql_08
  run env TELLER_DB_PASSWORD=pw zsh "${FIXTURE_ROOT}/08_verify_updated_at_trigger_coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ PASS:"* ]]
}
