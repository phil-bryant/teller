# Teller Institution Requirements

## Scope

Applies to `src/teller/teller_institution.py`.

R600  Statement: Define institution ORM mapping with stable identifier and display-name fields.
Design: `TellerInstitution` maps institution identifier and unique display-name columns for account linkage.
Tests:
- R600-T01: Verify institution model maps id/name columns with expected metadata (`tests/py/test_teller_institution.py`).
