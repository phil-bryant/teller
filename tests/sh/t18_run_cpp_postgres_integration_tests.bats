#!/usr/bin/env bats
# Self-contained shell unit tests for tests/t18_run_cpp_postgres_integration_tests.sh,
# the teller-owned C++ PostgreSQL integration lane. These assert its credential
# resolution/skip, strict psql, and scratch-database cleanup contract.

#R001: function tag for setup
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd -P)"
  SCRIPT="${REPO_ROOT}/tests/t18_run_cpp_postgres_integration_tests.sh"
}

@test "lane resolves admin credentials and skips cleanly when absent" {
  #R001-T01: env_item_field/conninfo resolution with a clean skip path.
  run grep -q 'env_item_field()' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'TELLER_TEST_PG_ADMIN_CONNINFO' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'no PostgreSQL admin credentials' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "lane runs admin psql non-interactively with strict error stops" {
  #R005-T01: run_psql enforces -w and ON_ERROR_STOP=1.
  run grep -q 'run_psql()' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'psql -w -v ON_ERROR_STOP=1' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "lane always drops the scratch database via an EXIT trap" {
  #R010-T01: cleanup trap drops the scratch database.
  run grep -q 'trap cleanup EXIT' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q 'DROP DATABASE IF EXISTS' "$SCRIPT"
  [ "$status" -eq 0 ]
}
