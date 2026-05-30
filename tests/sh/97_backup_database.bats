#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  create_repo_fixture
  copy_script_to_fixture "97_backup_database.sh"
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
  cat > "${STUB_BIN}/shasum" <<'EOF'
#!/usr/bin/env bash
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

@test "fails when pg_dump is missing" {
  #R001-T01 #R005-T01 #R010-T01 #R015-T01
  stub_cmd 1psa "echo pass"
  stub_cmd pg_dumpall "exit 0"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pg_dump is required"* ]]
}

@test "creates dump and globals artifacts with printed paths" {
  #R020-T01 #R025-T01 #R030-T01 #R035-T01 #R040-T01 #R050-T01 #R055-T01 #R055-T02
  stub_cmd 1psa "echo pass"
  cat > "${STUB_BIN}/pg_dump" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-f" ]]; then
    touch "$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dump"
  cat > "${STUB_BIN}/pg_dumpall" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-f" ]]; then
    touch "$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dumpall"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup written:"* ]]
  [[ "$output" == *"Globals written:"* ]]
  [[ "$output" == *"Manifest written:"* ]]
  [[ "$output" == *"local_prod_"* ]]
  run bash -c "ls -1 '${FIXTURE_ROOT}/backups/'*.manifest.sha256"
  [ "$status" -eq 0 ]
  manifest_path="$output"
  run bash -c "stat -f %Lp '${manifest_path}'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 600 ]
}

@test "managed target writes schema-scoped dump and skips globals" {
  #R040-T02 #R045-T01 #R045-T02
  cat > "${FIXTURE_ROOT}/src/scripts/db_profile_export.sh" <<'EOF'
#!/usr/bin/env bash
#R045: Stub helper mirrors a managed Supabase profile resolution for backup tests.
profile="default"
while (($#)); do
  case "$1" in
    --profile) shift; profile="${1:-}";;
  esac
  shift
done
if [[ "$profile" == "supabase_direct" ]]; then
  echo "PROFILE_NAME=supabase_direct"
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
  stub_cmd 1psa "echo managed-pass"
  cat > "${STUB_BIN}/pg_dump" <<EOF
#!/usr/bin/env bash
echo pg_dump "\$*" >> "${CALLS_LOG}"
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == "-f" ]]; then
    touch "\$2"
    shift 2
    continue
  fi
  shift
done
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dump"
  cat > "${STUB_BIN}/pg_dumpall" <<EOF
#!/usr/bin/env bash
echo pg_dumpall "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/pg_dumpall"

  run bash "${FIXTURE_ROOT}/97_backup_database.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup written:"* ]]
  [[ "$output" == *"Globals skipped:"* ]]
  [[ "$output" == *"supabase_direct_postgres_"* ]]
  calls="$(<"${CALLS_LOG}")"
  [[ "$calls" == *"-n teller"* ]]
  [[ "$calls" != *"pg_dumpall "* ]]
}
