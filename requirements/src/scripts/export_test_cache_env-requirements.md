# Export Test Cache Env Requirements

## Scope

Applies to `src/scripts/export_test_cache_env.sh`.

R001  Statement: Export canonical cache locations for Python test tooling.
Design: Define `export_test_cache_env(repo_root)` to set `CACHE_ROOT`, `PYTHONPYCACHEPREFIX`, `RUFF_CACHE_DIR`, and `HYPOTHESIS_STORAGE_DIRECTORY` under `${repo_root}/artifacts/cache/` and create those directories.
Tests:
- R001-T01: Traceability anchor in `tests/sh/run_unit_test_lanes.bats`.

R005  Statement: Default Hypothesis storage away from repository-root `.hypothesis`.
Design: When `HYPOTHESIS_STORAGE_DIRECTORY` is unset, set it to `${CACHE_ROOT}/hypothesis`.
Tests:
- R005-T01: Traceability anchor in `tests/py/test_hypothesis_storage_location.py`.
