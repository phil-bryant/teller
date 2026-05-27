---
name: repo-clutter-structure
overview: Analyze root-level clutter and propose a safer repository layout with optional new directories, compatibility strategy, and migration steps.
todos:
  - id: inventory-hardcoded-paths
    content: Inventory and classify every root-path assumption in scripts/tests/docs (movable vs fixed).
    status: completed
  - id: artifacts-dir-consolidation
    content: Define `artifacts/*` target structure and map each current output directory/file to a destination.
    status: completed
  - id: config-local-relocation
    content: Design profile config relocation to `config/local/` with backward-compatible fallback order and test/doc updates.
    status: completed
isProject: false
---

# Teller Root Clutter Cleanup Plan

## What the analysis shows
- Root clutter is mostly in three categories: generated runtime artifacts, operational entrypoint scripts, and local environment/config files.
- Several paths are currently hard-coded to root defaults and should not be moved blindly:
  - `.security-reports` and `.security-venv` defaults are embedded in [`/Users/phil/local/src/teller/06_run_static_security_tests.sh`](/Users/phil/local/src/teller/06_run_static_security_tests.sh), [`/Users/phil/local/src/teller/05_run_av_test.sh`](/Users/phil/local/src/teller/05_run_av_test.sh), [`/Users/phil/local/src/teller/13_run_fuzz_tests.sh`](/Users/phil/local/src/teller/13_run_fuzz_tests.sh), and [`/Users/phil/local/src/teller/24_run_all_tests_parallel.sh`](/Users/phil/local/src/teller/24_run_all_tests_parallel.sh).
  - `db-profiles.json` is expected in root by docs/tests unless overridden, including references in [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md), [`/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py`](/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py), and shell tests under [`/Users/phil/local/src/teller/tests/sh`](/Users/phil/local/src/teller/tests/sh).

## Proposed new directories
- `artifacts/`
  - `artifacts/security/` (target for `.security-reports`)
  - `artifacts/parallel/` (target for `.parallel-checks-reports`)
  - `artifacts/mutation/` (target for `mutants` outputs)
  - `artifacts/fuzz/` (optional consolidation for fuzz lane output)
- `config/local/`
  - candidate home for local profile configs (`db-profiles.local.json`, optional `db-profiles.json`) once scripts are made path-aware by default.

## Keep-at-root (or do not move)
- Keep root-only project metadata at root: [`/Users/phil/local/src/teller/pyproject.toml`](/Users/phil/local/src/teller/pyproject.toml), [`/Users/phil/local/src/teller/requirements.txt`](/Users/phil/local/src/teller/requirements.txt), [`/Users/phil/local/src/teller/requirements-security.txt`](/Users/phil/local/src/teller/requirements-security.txt), [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md).
- Treat these as generated and ignore/clean rather than relocate manually: `__pycache__`, `.pytest_cache`, `.ruff_cache`, `.hypothesis`, `teller.egg-info`.
- Keep virtualenvs where current scripts expect them unless intentionally refactoring defaults (`teller-venv`, `.security-venv`).

## Migration strategy (safe)
- Phase 1: Standardize generated outputs behind env vars and defaults, without moving entrypoint scripts.
  - Add canonical defaults in one shared shell helper and route lanes to `artifacts/*`.
  - Preserve current paths as fallbacks during transition.
- Phase 2: Move local config files to `config/local/` only after widening profile-file resolution order and updating tests/docs.
- Phase 3: Keep numbered `*.sh` entrypoints at root and reduce clutter by routing outputs/config to dedicated directories instead of relocating operational scripts.

## Concrete recommendations from `clutter.txt`
- Good candidates for relocation via script defaults:
  - `.security-reports` -> `artifacts/security`
  - `.parallel-checks-reports` -> `artifacts/parallel`
  - `mutants` -> `artifacts/mutation`
- Good candidates for “leave and ignore”:
  - `.hypothesis`, `.pytest_cache`, `.ruff_cache`, `__pycache__`, `teller.egg-info`
- Keep at root:
  - `db-profiles.json`, `db-profiles-EXAMPLE.json`, numbered `*.sh` script entrypoints.

## Success criteria
- Root directory contains mostly source, docs, core metadata, and a minimal set of executable entrypoints.
- All test lanes still pass with either legacy paths or new `artifacts/*` locations.
- README and requirements docs reflect the final path conventions exactly.