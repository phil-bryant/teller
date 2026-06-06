# Teller Base Requirements

## Scope

Applies to `src/teller/teller_base.py`.

R600  Statement: Expose SQLAlchemy declarative registry and metadata from shared Base.
Design: Provide module-global declarative base that surfaces registry and metadata for teller models.
Tests:
- R600-T01: Verify Base exposes shared registry and metadata (`tests/py/test_teller_base.py`).

R605  Statement: Bind declarative subclasses to the shared base registry.
Design: Ensure subclasses register tables on shared Base metadata/registry and remain reusable across runs.
Tests:
- R605-T01: Verify declarative subclass binds to shared base registry (`tests/py/test_teller_base.py`).
