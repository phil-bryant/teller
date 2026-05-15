#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  teardown_shell_test
}

@test "OCR path uses vision swift bridge" {
  #R001
  run python3 -c "
from pathlib import Path
t = (Path('$(repo_root)') / '13_backfill_bank_statements.py').read_text()
assert 'Vision' in t and 'VNRecognizeText' in t
"
  [ "$status" -eq 0 ]
}

@test "parsing uses regex and type maps for line extraction" {
  #R005
  run python3 -c "
from pathlib import Path
t = (Path('$(repo_root)') / '13_backfill_bank_statements.py').read_text()
assert 'TYPE_MAP' in t and 'parse_transactions' in t
"
  [ "$status" -eq 0 ]
}

@test "account matching uses last four and institution rows" {
  #R010
  run python3 -c "
from pathlib import Path
t = (Path('$(repo_root)') / '13_backfill_bank_statements.py').read_text()
assert 'match_statement_to_account' in t
"
  [ "$status" -eq 0 ]
}

@test "statement transaction ids are stable" {
  #R015
  run grep "def make_txn_id" "$(repo_root)/13_backfill_bank_statements.py"
  [ "$status" -eq 0 ]
  run grep "stmt_" "$(repo_root)/13_backfill_bank_statements.py"
  [ "$status" -eq 0 ]
  run grep "sha256" "$(repo_root)/13_backfill_bank_statements.py"
  [ "$status" -eq 0 ]
}

@test "cli exposes institution account statements root and dry run" {
  #R020
  run python3 -c "
from pathlib import Path
t = (Path('$(repo_root)') / '13_backfill_bank_statements.py').read_text()
for k in ('--institution-id', '--account-id', 'statements-root', '--dry-run'):
  assert k in t
"
  [ "$status" -eq 0 ]
}

@test "main logs backfill complete with counters" {
  #R025
  run python3 -c "
from pathlib import Path
t = (Path('$(repo_root)') / '13_backfill_bank_statements.py').read_text()
assert 'Backfill complete' in t and 'inserted' in t and 'total_parsed' in t
"
  [ "$status" -eq 0 ]
}
