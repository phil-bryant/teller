#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

sql_file() {
  printf '%s' "$(repo_root)/sql/postgres/create_triggers.sql"
}

@test "defines update updated_at trigger function" {
  #R001
  run grep "update_updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "NEW.updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "iterates teller base tables for updated at" {
  #R005 #R010
  run grep "information_schema" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "replaces existing custom triggers" {
  #R015
  run grep -E "DROP TRIGGER|EXISTS" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "uses before update trigger name pattern" {
  #R020
  run grep "BEFORE UPDATE" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "update_%s_updated_at" "$(sql_file)"
  [ "$status" -eq 0 ]
}
