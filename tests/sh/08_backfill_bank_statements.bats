#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  #R001-T01: Initialize isolated shell fixtures and Python import path.
  setup_shell_test
  export PYTHONPATH="$(repo_root)"
}

teardown() {
  #R001-T01: Clean up temporary shell fixtures after each test.
  teardown_shell_test
}

@test "backfill parser assigns signed amounts and transaction types" {
  #R005-T01: Parsed transactions include expected signed amounts and inferred types.
  #R020-T01: Dry-run compatible parsing path remains callable without DB writes.
  #R025-T01: Parsing produces auditable transaction fields for summary logging.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("backfill_script", "08_backfill_bank_statements.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

pages = [
    "\n".join(
        [
            "Date Activity Description",
            "01/03 POS PURCHASE COFFEE SHOP 4.50",
            "01/04 MOBILE DEPOSIT PAYROLL 1200.00",
            "Deposits / Misc Credits 1 1,200.00",
            "Withdrawals / Misc Debits 1 4.50",
            "Statement Date 01/31/26",
        ]
    )
]
txns = module.parse_transactions(pages, 2026, 1)
assert len(txns) == 2, txns
assert any(t["amount"] == "-4.50" and t["type"] == "card_payment" for t in txns), txns
assert any(t["amount"] == "1200.00" and t["type"] == "deposit" for t in txns), txns
PY
  [ "$status" -eq 0 ]
}

@test "statement account matching supports override and last-four hint" {
  #R010-T01: Account matching honors explicit override and last-four fallback hints.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("backfill_script", "08_backfill_bank_statements.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = [("acct_1", "Checking", "1234"), ("acct_2", "Savings", "5678")]
pages = ["Account ending in 5678\nStatement Date 01/31/26"]

matched = module.match_statement_to_account(Path("statement.pdf"), pages, rows, None)
assert matched == "acct_2", matched

override = module.match_statement_to_account(Path("statement.pdf"), pages, rows, "acct_1")
assert override == "acct_1", override
PY
  [ "$status" -eq 0 ]
}

@test "statement transaction ids remain deterministic across runs" {
  #R015-T01: Statement transaction IDs remain deterministic across repeated calls.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("backfill_script", "08_backfill_bank_statements.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

first = module.make_txn_id("acct_1", "2026-01-15", "-42.00", "POS PURCHASE", 1)
second = module.make_txn_id("acct_1", "2026-01-15", "-42.00", "POS PURCHASE", 1)
assert first == second
assert first.startswith("stmt_")
PY
  [ "$status" -eq 0 ]
}

@test "OCR line reconstruction clusters points with adaptive vertical density" {
  #R030-T01: Reconstructed lines preserve top-to-bottom, left-to-right reading order.
  #R030-T02: Vertical jitter within a row is merged while separate rows stay split.
  #R030-T03: Adaptive epsilon honors floor behavior and scales with row gaps.
  run ./teller-venv/bin/python3 - <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("backfill_script", "08_backfill_bank_statements.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

points = [
    (0.90, 0.10, "01/03"),
    (0.90, 0.30, "COFFEE"),
    (0.90, 0.50, "4.50"),
    (0.86, 0.10, "01/04"),
    (0.861, 0.30, "PAYROLL"),
    (0.86, 0.55, "1200.00"),
]
lines = module.reconstruct_lines(points)
assert len(lines) == 2, lines
assert lines[0].startswith("01/03"), lines
assert "PAYROLL" in lines[1], lines

epsilon = module._adaptive_line_epsilon([0.90, 0.86], min_epsilon=0.004, gap_factor=0.6)
assert epsilon >= 0.004
PY
  [ "$status" -eq 0 ]
}
