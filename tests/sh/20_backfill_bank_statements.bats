#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

@test "backfill parser assigns signed amounts and transaction types" {
  #R001-T01 #R005-T01 #R020-T01 #R025-T01
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_20_backfill_bank_statements.BackfillParsingTests.test_parse_transactions_assigns_sign_and_type
  [ "$status" -eq 0 ]
}

@test "statement account matching supports override and last-four hint" {
  #R010-T01
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_20_backfill_bank_statements.BackfillParsingTests.test_match_statement_to_account_uses_override \
    tests.py.test_20_backfill_bank_statements.BackfillParsingTests.test_match_statement_to_account_uses_last_four_hint
  [ "$status" -eq 0 ]
}

@test "statement transaction ids remain deterministic across runs" {
  #R015-T01
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_20_backfill_bank_statements.BackfillParsingTests.test_make_txn_id_is_deterministic
  [ "$status" -eq 0 ]
}
