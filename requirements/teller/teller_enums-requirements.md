# Teller Enums Requirements

## Scope

Applies to `src/teller/teller_enums.py`.

R600  Statement: Preserve stable account-type enum values.
Design: Keep `TellerAccountType` value set stable across releases.
Tests:
- R600-T01: Verify account-type enum values remain stable (`tests/py/test_teller_enums.py`).

R605  Statement: Include common bank-product subtypes.
Design: Keep `TellerAccountSubtype` values covering common checking/savings/card product categories.
Tests:
- R605-T01: Verify account-subtype enum includes common bank products (`tests/py/test_teller_enums.py`).

R610  Statement: Preserve transaction-status enum values.
Design: Keep transaction status values constrained to posted/pending semantics.
Tests:
- R610-T01: Verify transaction-status enum values are posted/pending (`tests/py/test_teller_enums.py`).

R615  Statement: Preserve account-status enum values.
Design: Keep account status values constrained to open/closed states.
Tests:
- R615-T01: Verify account-status enum values are open/closed (`tests/py/test_teller_enums.py`).

R620  Statement: Preserve unknown phone-number enum sentinel.
Design: Keep identity phone-number enum supporting unknown-value passthrough.
Tests:
- R620-T01: Verify phone-number enum preserves unknown sentinel (`tests/py/test_teller_enums.py`).
