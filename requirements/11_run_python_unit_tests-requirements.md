# Run Python Unit Tests Requirements

## Scope

Applies to `tests/t08_run_python_unit_tests.sh`.

## Ownership Boundaries

This document owns wrapper behavior only.
Shared lane implementation details are owned by:
- `requirements/src/scripts/run_unit_test_lanes-requirements.md`

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory and `cd` there before invoking the shared unit-test lane runner.
Tests:
- R001-T01: Run from a different working directory and verify the wrapper still succeeds.

R005  Statement: Execute only the Python unit-test lane.
Design: Invoke `src/scripts/run_unit_test_lanes.sh` with `RUN_PYTHON_TESTS=true` and all other unit lanes disabled.
Tests:
- R005-T01: Verify the wrapper exports lane toggles with only Python tests enabled.

R008  Statement: Keep Hypothesis storage out of the repository root during Python unit tests.
Design: The shared lane runner sources `export_test_cache_env.sh`; `tests/py/conftest.py` also defaults `HYPOTHESIS_STORAGE_DIRECTORY` to `artifacts/cache/hypothesis` for direct pytest invocations.
Tests:
- R008-T01: Traceability anchor in `tests/py/test_hypothesis_storage_location.py`.
