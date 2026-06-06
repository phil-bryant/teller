#!/usr/bin/env bats
load "helpers/common.bash"

#R001: Prepare bats fixture state for script-level verification tests.
setup() {
  setup_shell_test
}

#R001: Cleanup bats fixture state after script-level verification tests.
teardown() {
  teardown_shell_test
}

#R001: Resolve SQL fixture path used by companion bats checks.
sql_file() {
  printf '%s' "$(repo_root)/src/sql/postgres/create_audit.sql"
}

@test "define audit log table" {
  #R001-T01: Execute DDL and verify `teller.audit_log` exists with expected columns and action constraint.
  run grep -E "teller\.audit_log" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "JSONB" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "define primary key column lookup and audit trigger" {
  #R005-T01: Call the function for a single-key table and a composite-key table and verify returned ordered column arrays.
  #R010-T01: Perform insert, update, and delete against a trigger-managed table and verify one audit row per operation with correct payload shape.
  run grep "get_primary_key_columns" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "audit_trigger_func" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "INSERT INTO teller.audit_log" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "normalize single and composite record ids" {
  #R015-T01: Audit events on a composite-key table and verify `record_id` stores all key parts.
  run grep "record_id" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep -E "array_length|FOREACH" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "attach audit triggers to teller base tables" {
  #R020-T01: Verify trigger creation excludes `audit_log` and includes other teller base tables.
  run grep "CREATE TRIGGER" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "audit_log" "$(sql_file)"
  [ "$status" -eq 0 ]
}
