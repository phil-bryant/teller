---
name: clutter-13-migration
overview: Answer all 13 clutter questions as yes and plan a coordinated migration so root-level items move into structured subdirectories without breaking scripts/tests/docs.
todos:
  - id: define-target-layout
    content: Define canonical destination paths for all 13 items and compatibility policy (fallbacks, env vars, and deprecation notes).
    status: completed
  - id: update-runtime-path-defaults
    content: Update shell/python defaults so caches/reports/venvs and mutation outputs resolve to new subdirectories with backward-compatible overrides.
    status: completed
  - id: relocate-db-profile-conventions
    content: Expand DB profile path resolution and update docs/tests to prefer config/ while preserving legacy root fallback.
    status: completed
  - id: refresh-security-and-deps-references
    content: Move or alias requirements-security and security policy path references and update all scripts/docs consuming them.
    status: completed
  - id: verify-and-cleanup
    content: Run impacted lanes/tests, confirm outputs land in new directories, and finalize ignore/cleanup strategy for legacy paths.
    status: in_progress
isProject: false
---

# Root Clutter 13-Item Migration Plan

## Answers To `clutter.txt`
All 13 questions are **Yes** under your rule ("yes even if coordinated updates are needed").

- 1 `.hypothesis` → yes
- 2 `.parallel-checks-reports` → yes
- 3 `.pytest_cache` → yes
- 4 `.ruff_cache` → yes
- 5 `.security-reports` → yes
- 6 `.security-venv` → yes
- 7 `.zap` → yes
- 8 `db-profiles-EXAMPLE.json` → yes
- 9 `db-profiles.json` → yes
- 10 `mutants` → yes
- 11 `requirements-security.txt` → yes
- 12 `security` → yes
- 13 `teller.egg-info` → yes

## 13-Line Relocation Summary
1. `.hypothesis` -> `artifacts/cache/hypothesis/`
2. `.parallel-checks-reports` -> `artifacts/parallel/`
3. `.pytest_cache` -> `artifacts/cache/pytest/`
4. `.ruff_cache` -> `artifacts/cache/ruff/`
5. `.security-reports` -> `artifacts/security/reports/`
6. `.security-venv` -> `artifacts/venv/security/`
7. `.zap` -> `artifacts/security/zap-home/`
8. `db-profiles-EXAMPLE.json` -> `config/db-profiles-EXAMPLE.json`
9. `db-profiles.json` -> `config/db-profiles.json`
10. `mutants` -> `artifacts/mutation/mutants/`
11. `requirements-security.txt` -> `requirements/security/requirements-security.txt`
12. `security` -> `config/security/`
13. `teller.egg-info` -> `artifacts/cache/egg-info/teller.egg-info/`

## Target Layout
Use a stable root convention:

- `artifacts/cache/` for tool caches (`.hypothesis`, `.pytest_cache`, `.ruff_cache`, `teller.egg-info` if preserved)
- `artifacts/parallel/` for `.parallel-checks-reports`
- `artifacts/security/` for `.security-reports` and ZAP runtime home currently under `.zap`
- `artifacts/mutation/` for `mutants`
- `config/` for `db-profiles.json` and `db-profiles-EXAMPLE.json`
- `requirements/security/` for `requirements-security.txt`
- `config/security/` for root `security` policy files
- `artifacts/venv/` for `.security-venv`

## Code/Script Surfaces To Update
- Shell lane defaults and excludes in [`/Users/phil/local/src/teller/06_run_static_security_tests.sh`](/Users/phil/local/src/teller/06_run_static_security_tests.sh), [`/Users/phil/local/src/teller/22_run_dynamic_security_tests.sh`](/Users/phil/local/src/teller/22_run_dynamic_security_tests.sh), [`/Users/phil/local/src/teller/05_run_av_test.sh`](/Users/phil/local/src/teller/05_run_av_test.sh), and [`/Users/phil/local/src/teller/11_run_mutation_tests.sh`](/Users/phil/local/src/teller/11_run_mutation_tests.sh).
- Parallel runner/report defaults in [`/Users/phil/local/src/teller/24_run_all_tests_parallel.sh`](/Users/phil/local/src/teller/24_run_all_tests_parallel.sh).
- DB profile resolver/search order in [`/Users/phil/local/src/teller/src/teller/teller_db_profile.py`](/Users/phil/local/src/teller/src/teller/teller_db_profile.py), plus dependent tests in [`/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py`](/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py) and shell tests in [`/Users/phil/local/src/teller/tests/sh`](/Users/phil/local/src/teller/tests/sh).
- Dependency/security policy defaults in [`/Users/phil/local/src/teller/04_run_dependency_freshness_tests.sh`](/Users/phil/local/src/teller/04_run_dependency_freshness_tests.sh) and related scripts consuming root `security/` JSONs.
- Documentation and usage examples in [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md) and `requirements/*-requirements.md` files that encode path expectations.

## Migration Strategy

### Phase 1: Add new canonical defaults with compatibility
- Introduce env-backed default paths pointing to the new subdirs.
- Keep current root/legacy paths as fallback read locations and accepted excludes.
- Keep script UX stable (same commands still work).

### Phase 2: Move conventions and references
- Update docs/tests to advertise new locations first.
- Adjust copy/setup guidance strings (e.g., DB profile bootstrap and security requirements install paths).
- Ensure scanner excludes and artifact paths no longer re-ingest generated scanner output.

### Phase 3: Verification and deprecation posture
- Run representative lanes (`04`, `05`, `06`, `11`, `22`, `24`) plus DB profile tests.
- Confirm outputs land under `artifacts/*`, `config/*`, and `requirements/security/` (including `artifacts/venv/security/`).
- Verify `./24_run_all_tests_parallel.sh` reports an all-green result after relocation changes.
- Retain legacy fallback support for one migration window; then optionally remove in a follow-up.

## Success Criteria
- Root no longer accumulates the 13 clutter items during normal workflows.
- Existing commands remain functional without manual user rewiring.
- Tests and README align with the new canonical paths.
- `./24_run_all_tests_parallel.sh` completes with all checks green.
- Legacy paths are either auto-routed, ignored, or explicitly documented as deprecated fallback behavior.