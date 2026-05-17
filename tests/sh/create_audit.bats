#!/usr/bin/env bats

# Traceability numbered tags for requirements/sql/create_audit-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

sql_file() {
  printf '%s' "$(repo_root)/sql/postgres/create_audit.sql"
}

@test "define audit log table" {
  #R001
  run grep -E "teller\.audit_log" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "JSONB" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "define primary key column lookup and audit trigger" {
  #R005 #R010
  run grep "get_primary_key_columns" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "audit_trigger_func" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "INSERT INTO teller.audit_log" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "normalize single and composite record ids" {
  #R015
  run grep "record_id" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep -E "array_length|FOREACH" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "attach audit triggers to teller base tables" {
  #R020
  run grep "CREATE TRIGGER" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "audit_log" "$(sql_file)"
  [ "$status" -eq 0 ]
}
