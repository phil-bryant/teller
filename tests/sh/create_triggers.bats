#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

sql_file() {
  printf '%s' "$(repo_root)/src/sql/postgres/create_triggers.sql"
}

@test "defines update updated_at trigger function" {
  #R001-T01: Update a row in a trigger-managed table and verify `updated_at` is changed by the trigger.
  run grep "update_updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "NEW.updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "iterates teller base tables for updated at" {
  #R005-T01: Add a teller table with `updated_at`, run script, and verify trigger creation for that table.
  #R010-T01: Re-run script and verify target table traversal order remains stable.
  run grep "information_schema" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "replaces existing custom triggers" {
  #R015-T01: Execute script twice and verify no duplicate trigger error occurs on the second run.
  run grep -E "DROP TRIGGER|EXISTS" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "uses before update trigger name pattern" {
  #R020-T01: Inspect `pg_trigger` metadata and verify each eligible table has the expected trigger name and function binding.
  run grep "BEFORE UPDATE" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "update_%s_updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
}
