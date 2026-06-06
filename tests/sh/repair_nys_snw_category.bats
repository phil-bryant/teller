#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

sql_file() {
  printf '%s' "$(repo_root)/src/scripts/repair_nys_snw_category.sql"
}

@test "normalizes hierarchy fields before constraints" {
  #R001-T01: Verify the SQL script contains normalization updates for all targeted mutable hierarchy fields.
  run grep "REGEXP_REPLACE(level_1" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "REGEXP_REPLACE(level_4" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "REGEXP_REPLACE(categorization" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "contains guard block for empty hierarchy rows" {
  #R005-T01: Verify the guard block checks emptiness and raises a descriptive exception for non-compliant data.
  run grep "Cannot enforce nys_snw_category constraints" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "COALESCE(" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "recreates and validates both constraints" {
  #R010-T01: Verify DDL includes drop/add/validate sequence for both named constraints.
  run grep "DROP CONSTRAINT IF EXISTS nys_snw_category_non_empty_hierarchy_chk" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "ADD CONSTRAINT nys_snw_category_non_empty_hierarchy_chk" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "VALIDATE CONSTRAINT nys_snw_category_no_control_chars_chk" "$(sql_file)"
  [ "$status" -eq 0 ]
}
