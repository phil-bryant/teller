# Teller Transaction Requirements

## Scope

Applies to `src/teller/teller_transaction.py`.

R600  Statement: Define transaction ORM mapping with stable account relationship binding.
Design: `TellerTransaction` declares canonical mapped columns and an explicit account relationship join path.
Tests:
- R600-T01: Verify transaction model declares account relationship join metadata (`tests/py/test_teller_transaction.py`).
