#!/usr/bin/env bats

# Traceability numbered tags for requirements/19_backfill_bank_statements-requirements.md
# #R001-T01: Traceability anchor.
# #R005-T01: Traceability anchor.
# #R010-T01: Traceability anchor.
# #R015-T01: Traceability anchor.
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.

load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

@test "backfill parser assigns signed amounts and transaction types" {
  #R005
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_19_backfill_bank_statements.BackfillParsingTests.test_parse_transactions_assigns_sign_and_type
  [ "$status" -eq 0 ]
}

@test "statement account matching supports override and last-four hint" {
  #R010
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_19_backfill_bank_statements.BackfillParsingTests.test_match_statement_to_account_uses_override \
    tests.py.test_19_backfill_bank_statements.BackfillParsingTests.test_match_statement_to_account_uses_last_four_hint
  [ "$status" -eq 0 ]
}

@test "statement transaction ids remain deterministic across runs" {
  #R015
  run ./teller-venv/bin/python3 -m unittest \
    tests.py.test_19_backfill_bank_statements.BackfillParsingTests.test_make_txn_id_is_deterministic
  [ "$status" -eq 0 ]
}
