---
name: Harden ingest/runtime safety
overview: Fix the timezone mismatch between ORM timestamp column configuration and naive datetime defaults in the shared ORM base.
todos:
  - id: tz-aware-defaults
    content: Replace naive datetime defaults in TimestampMixin and add aware-datetime assertions in teller_object tests
    status: completed
  - id: validate-focused-tests
    content: Run focused teller_object tests validating timezone-aware timestamp defaults
    status: completed
isProject: false
---

# Fix ORM timestamp timezone mismatch

## Targeted Changes

- **Timezone-aware ORM defaults**
  - Update [`src/teller/teller_object.py`](src/teller/teller_object.py) `TimestampMixin` to replace naive `datetime.utcnow` defaults/onupdate with timezone-aware UTC factories (e.g. `datetime.now(timezone.utc)`), keeping `DateTime(timezone=True)` semantics consistent.
  - Add/adjust tests in [`tests/py/test_teller_object.py`](tests/py/test_teller_object.py) to assert timestamp defaults produce timezone-aware datetimes (not just that defaults exist).

## Validation Plan

- Run focused Python tests for [`tests/py/test_teller_object.py`](tests/py/test_teller_object.py).

## Expected Outcome

- Timestamp columns in ORM defaults are consistently timezone-aware.
