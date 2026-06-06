# Teller Account Requirements

## Scope

Applies to `src/teller/teller_account.py`.

R600  Statement: Fetch account details via API client links and store hydrated results.
Design: `get_details()` calls the configured API client with account detail link and stores the hydrated details object.
Tests:
- R600-T01: Verify `get_details()` reads API client response and stores hydrated details (`tests/py/test_teller_account.py`).
