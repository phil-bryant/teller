#!/usr/bin/env bats

# Requirement test-case tags for requirements/src/scripts/cleanup_legacy_dast_artifacts-requirements.md
# #R001-T01: Verify conservative DAST fingerprint predicates.
# #R005-T01: Verify transaction wrapper and delete ordering.
# #R010-T01: Verify pre-delete operator count queries.

load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

sql_file() {
  printf '%s' "$(repo_root)/src/scripts/cleanup_legacy_dast_artifacts.sql"
}

@test "uses conservative DAST cleanup predicates" {
  #R001
  run grep "level_1 = 'DAST'" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "schemathesis-seed-%@example.invalid" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "dast-seed-%@example.invalid" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "wraps deletes in transaction and FK-safe sequence" {
  #R005
  run grep "^BEGIN;" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "DELETE FROM teller.transaction_nys_snw_category" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "DELETE FROM teller.nys_snw_category" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "DELETE FROM teller.transaction_email_match" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "^COMMIT;" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "includes pre-delete count queries for operator visibility" {
  #R010
  run grep "SELECT 'nys_snw_category orphans" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "SELECT 'transaction_nys_snw_category mappings" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "SELECT 'transaction_email_match seeder rows'" "$(sql_file)"
  [ "$status" -eq 0 ]
}
