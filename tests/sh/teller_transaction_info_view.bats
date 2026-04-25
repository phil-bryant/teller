#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

sql_file() {
  printf '%s' "$(repo_root)/sql/postgres/teller_transaction_info_view.sql"
}

@test "view joins transaction to related teller data" {
  #R001
  run grep "teller\.transaction_info_view" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "JOIN" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "view orders by date and description" {
  #R005
  run grep "ORDER BY" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "tt.date" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "tt.description" "$(sql_file)"
  [ "$status" -eq 0 ]
}
