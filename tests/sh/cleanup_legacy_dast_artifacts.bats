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
  printf '%s' "$(repo_root)/src/scripts/cleanup_legacy_dast_artifacts.sql"
}

@test "uses conservative DAST cleanup predicates" {
  #R001-T01: Verify script predicates constrain deletions to expected DAST fingerprint columns/values.
  run grep "level_1 = 'DAST'" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "schemathesis-seed-%@example.invalid" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "dast-seed-%@example.invalid" "$(sql_file)"
  [ "$status" -eq 0 ]
}

@test "wraps deletes in transaction and FK-safe sequence" {
  #R005-T01: Verify script contains explicit `BEGIN/COMMIT` and dependency-ordered delete statements.
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
  #R010-T01: Verify script contains pre-delete counting queries for each cleanup domain.
  run grep "SELECT 'nys_snw_category orphans" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "SELECT 'transaction_nys_snw_category mappings" "$(sql_file)"
  [ "$status" -eq 0 ]
  run grep "SELECT 'transaction_email_match seeder rows'" "$(sql_file)"
  [ "$status" -eq 0 ]
}
