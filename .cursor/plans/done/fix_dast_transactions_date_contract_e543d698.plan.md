---
name: Fix DAST Transactions Date Contract
overview: Identify and repair the `/v1/transactions` date-validation contract mismatch that now fails Schemathesis stateful positive-mode tests, while preserving intended friendly error behavior.
todos:
  - id: confirm-regression-boundary
    content: Validate and document commit-level regression boundary around `99f7843` + DAST strict mode interactions.
    status: completed
  - id: patch-schemathesis-fixture-transactions-dates
    content: Extend fixture prep to constrain `/v1/transactions` date query params to semantically valid date generation for DAST artifacts.
    status: completed
  - id: align-openapi-transactions-date-semantics
    content: Adjust API/OpenAPI query param definitions so `/v1/transactions` date semantics are represented in the schema.
    status: completed
  - id: update-date-validation-tests
    content: Update/add unit+contract tests for friendly date errors and schema/runtime alignment.
    status: completed
  - id: rerun-t12-and-verify
    content: Run t12 DAST lane and verify Schemathesis stateful passes with no contract mismatch for transaction dates.
    status: completed
isProject: false
---

# Fix DAST `/v1/transactions` Date Contract Regression

## What happened
- A recent validation hardening commit changed `/v1/transactions` date handling to return friendly errors for malformed dates, including runtime semantic checks via `date.fromisoformat`, while query params remained regex-based string fields in OpenAPI.
- In `SCHEMATHESIS_MODE=positive`, Schemathesis generates requests that are valid per OpenAPI regex but invalid as real calendar dates (for example month `16`), so API returns `400` and Schemathesis flags a contract failure.
- Prior fixture hardening only targeted `/v1/matchy/messages/search`, not `/v1/transactions`, so this endpoint remains vulnerable to schema/runtime mismatch during fuzzing/stateful checks.

## Evidence to anchor changes
- Runtime semantic date validation and friendly error path in [`/Users/phil/local/src/teller/src/teller/classification/app.py`](/Users/phil/local/src/teller/src/teller/classification/app.py).
- Existing Schemathesis fixture tightening only for matchy search in [`/Users/phil/local/src/teller/tests/py/security/schemathesis_fixture_prep.py`](/Users/phil/local/src/teller/tests/py/security/schemathesis_fixture_prep.py).
- DAST lane uses positive mode by default in [`/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh).
- Regression originates near commit `99f7843` (friendly transaction date errors), exposed by stricter DAST setup from `07a3b2b` and partial fixture hardening in `8e0d5a6`.

## Implementation approach
1. **Immediate unblock for DAST lane**
   - Extend fixture preparation in [`/Users/phil/local/src/teller/tests/py/security/schemathesis_fixture_prep.py`](/Users/phil/local/src/teller/tests/py/security/schemathesis_fixture_prep.py) to tighten `/v1/transactions` `start_date` and `end_date` generation for Schemathesis runs.
   - Enforce `format: date` (and/or stricter constraints) in the prepared schema artifact used by DAST so generated dates are semantically valid.

2. **Durable contract alignment in API schema**
   - Update transaction query parameter typing in [`/Users/phil/local/src/teller/src/teller/classification/app.py`](/Users/phil/local/src/teller/src/teller/classification/app.py) so OpenAPI communicates real date semantics (instead of permissive string regex alone).
   - Keep friendly error messaging behavior consistent for malformed dates through existing validation/error handler flow, adjusting tests only where status/error provenance changes are intentional.

3. **Regression coverage and verification**
   - Add/adjust focused tests in [`/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py`](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py) and, if needed, contract tests in [`/Users/phil/local/src/teller/tests/py/test_frontend_backend_contract_scenarios.py`](/Users/phil/local/src/teller/tests/py/test_frontend_backend_contract_scenarios.py) to lock behavior.
   - Re-run `./tests/t12_run_dynamic_security_tests.sh` and confirm Schemathesis stateful phase passes without the date-format false positive.

## Expected outcome
- Schemathesis no longer generates schema-valid-but-calendar-invalid dates for `/v1/transactions` in positive mode.
- API and OpenAPI validation semantics are aligned, reducing future contract drift and recurring DAST regressions.
