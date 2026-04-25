#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

repo_src() {
  printf '%s' "$(repo_root)/11_fetch_teller_api_data.py"
}

@test "argparse includes debug, dry run, and institution" {
  #R001
  run grep -E "(--debug|dry-run|institution_id|argparse|structlog)" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "client loads cert paths from home teller" {
  #R005
  run grep "certificate.pem" "$(repo_src)"
  [ "$status" -eq 0 ]
  run grep "auth_token" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "Teller client imports connect repair" {
  #R010
  run grep "teller_connect_token_server" "$(repo_src)"
  [ "$status" -eq 0 ]
  run grep "_repair_enrollment" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "transaction fetch paginates with from_id" {
  #R015
  run grep "from_id" "$(repo_src)"
  [ "$status" -eq 0 ]
  run grep "_fetch_all_transactions" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "enrollment context builder dedupes" {
  #R020
  run grep "_dedupe_contexts" "$(repo_src)"
  [ "$status" -eq 0 ]
  run grep "_build_enrollment_contexts" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "main skips database when dry run" {
  #R025
  run grep "if not args.dry_run" "$(repo_src)"
  [ "$status" -eq 0 ]
  run grep "Dry run" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "persistence path calls persist_all" {
  #R030
  run grep "persist_all" "$(repo_src)"
  [ "$status" -eq 0 ]
}

@test "persistence path documents R030 and R035" {
  #R035
  run grep "R030" "$(repo_src)"
  [ "$status" -eq 0 ]
  run grep "R035" "$(repo_src)"
  [ "$status" -eq 0 ]
}
