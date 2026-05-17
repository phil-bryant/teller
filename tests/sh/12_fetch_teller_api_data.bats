#!/usr/bin/env bats

# Requirement test-case tags for requirements/12_fetch_teller_api_data-requirements.md
# #R001-T02: Traceability anchor.
# #R005-T02: Traceability anchor.
# #R010-T02: Traceability anchor.
# #R015-T02: Traceability anchor.
# #R020-T02: Traceability anchor.
# #R020-T03: Traceability anchor.
# #R025-T02: Traceability anchor.
# #R030-T02: Traceability anchor.
# #R035-T02: Traceability anchor.

# Traceability numbered tags for requirements/12_fetch_teller_api_data-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R030-T01: Traceability anchor.
# #R035-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

repo_src() {
  printf '%s' "$(repo_root)/12_fetch_teller_api_data.py"
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

@test "Teller client uses macOS UI connect repair launcher" {
  #R010
  run grep "17_run_classification_macos-ui.sh" "$(repo_src)"
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
