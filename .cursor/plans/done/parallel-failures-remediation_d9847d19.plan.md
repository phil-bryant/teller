---
name: parallel-failures-remediation
overview: Fix all currently failing parallel lanes by addressing root causes directly (no suppression), then align traceability requirements/tests/docs and re-validate the full suite.
todos:
  - id: fix-dependency-freshness
    content: Update `requirements.txt` direct outdated package(s) and verify `04_run_dependency_freshness_tests.sh` passes.
    status: completed
  - id: fix-python-unit-mapping
    content: Resolve SQLAlchemy duplicate table mapping in `tests/py/test_teller_object.py` and verify `10_run_python_unit_tests.sh` passes.
    status: completed
  - id: fix-sast-findings
    content: Remediate Semgrep/Bandit/Ruff blocking findings in `dast_cleanup.py`, `18_fetch_teller_api_data.py`, and `test_teller_mailcart_client.py`; rerun `06_run_static_security_tests.sh`.
    status: completed
  - id: fix-traceability-tags
    content: Add missing source `#R` and test `#Rxxx-Tyy` tags across failing traceability files and rerun `00_run_requirements_traceability_tests.sh`.
    status: completed
  - id: update-requirements-docs
    content: Update impacted requirements markdown docs/changelogs so new behavior and test mappings stay accurate.
    status: completed
  - id: full-regression
    content: Run `24_run_all_tests_parallel.sh` and confirm all lanes pass with no suppression.
    status: completed
isProject: false
---

# Fix Parallel Test Failures Without Suppression

## Objectives
- Restore passing status for the failing lanes from `24_run_all_tests_parallel.sh`:
  - dependency freshness (`04_run_dependency_freshness_tests.sh`)
  - Python unit tests (`10_run_python_unit_tests.sh`)
  - requirements traceability (`00_run_requirements_traceability_tests.sh`)
  - static security gate (`06_run_static_security_tests.sh`)
- Make required requirements/test/documentation updates so traceability and behavior stay consistent.

## Root Causes Confirmed
- Dependency freshness is failing on outdated direct requirement (`hypothesis`) in [requirements.txt](requirements.txt).
- Python unit tests fail with duplicate SQLAlchemy table mapping because test class in [tests/py/test_teller_object.py](tests/py/test_teller_object.py) collides with production model table (`teller.transaction_details`) from [src/teller/teller_transaction_details.py](src/teller/teller_transaction_details.py).
- Requirements traceability fails due missing source `#R` tags and missing numbered test tags across six requirement docs.
- SAST gate fails on:
  - dynamic SQL construction in [src/scripts/dast_cleanup.py](src/scripts/dast_cleanup.py)
  - missing request timeout in [18_fetch_teller_api_data.py](18_fetch_teller_api_data.py)
  - duplicated module block in [tests/py/test_teller_mailcart_client.py](tests/py/test_teller_mailcart_client.py)

## Closure Note
- `full-regression` is treated as superseded historical validation: a later completed plan ([`.cursor/plans/done/fix-parallel-failures_1030ed6d.plan.md`](.cursor/plans/done/fix-parallel-failures_1030ed6d.plan.md)) already captured the full-suite revalidation closure.
- Script numbering later changed from `24_*` to `10_*`; current equivalent orchestrator is [`10_run_all_tests_parallel.sh`](10_run_all_tests_parallel.sh).

## Implementation Plan
1. **Fix dependency freshness failure**
   - Update direct pinned dependency in [requirements.txt](requirements.txt) to current patch release for `hypothesis`.
   - Re-run `04_run_dependency_freshness_tests.sh` and confirm no direct-outdated failures.

2. **Fix Python unittest import/mapping failure**
   - Update test-only model in [tests/py/test_teller_object.py](tests/py/test_teller_object.py) to avoid table-name collision with production mapping by explicitly using a unique test table name (or unique schema-qualified table identity) while preserving requirement coverage assertions.
   - Re-run `10_run_python_unit_tests.sh` to validate full discovery pass.

3. **Remediate SAST findings by code changes (no ignores/no policy weakening)**
   - Replace dynamic `text(f"...NOT IN ({placeholders})...")` SQL in [src/scripts/dast_cleanup.py](src/scripts/dast_cleanup.py) with a bound-parameter approach using static SQL and array semantics (`ANY`) to satisfy Semgrep SQL-injection rules.
   - Add explicit timeout handling to Teller API HTTP requests in [18_fetch_teller_api_data.py](18_fetch_teller_api_data.py) (initial call and repair retry path) and cover via/alongside existing tests.
   - Remove duplicate second module block in [tests/py/test_teller_mailcart_client.py](tests/py/test_teller_mailcart_client.py), keep a single canonical test class, and preserve any unique assertions from the duplicate section.
   - Re-run `06_run_static_security_tests.sh` and verify gate passes.

4. **Fix requirements traceability failures (source/test tag alignment)**
   - Add missing source `#R` tags in:
     - [11_run_mutation_tests.sh](11_run_mutation_tests.sh) (`R045`, `R050`, `R055`)
     - [15_run_macos_ui_regression_tests.sh](15_run_macos_ui_regression_tests.sh) (`R055`, `R060`, `R065`, `R070`)
     - [20_run_classification_api.py](20_run_classification_api.py) (`R015`)
     - [22_run_dynamic_security_tests.sh](22_run_dynamic_security_tests.sh) (`R030`)
     - [src/macos-ui/Sources/TransactionClassifier/ContentView.swift](src/macos-ui/Sources/TransactionClassifier/ContentView.swift) (`R055`, `R060`, `R065`)
   - Add/fix missing numbered requirement test tags in:
     - [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift) (`R070-T01`, `R060-T02`)
     - [tests/sh/20_run_classification_api.bats](tests/sh/20_run_classification_api.bats) (`R015-T01`, `R015-T02`)
     - [tests/sh/22_run_dynamic_security_tests.bats](tests/sh/22_run_dynamic_security_tests.bats) (`R030-T01`, `R030-T02`)
     - [tests/py/test_teller_classification_api.py](tests/py/test_teller_classification_api.py) (`R040-T03`)
   - Re-run `00_run_requirements_traceability_tests.sh` to confirm all 55 checks pass.

5. **Update requirements/docs where behavior changed**
   - Add/adjust requirement text + changelog entries where code behavior becomes stricter or newly explicit:
     - [requirements/18_fetch_teller_api_data-requirements.md](requirements/18_fetch_teller_api_data-requirements.md) for HTTP timeout requirement and test mapping.
     - [requirements/src/scripts/dast_cleanup-requirements.md](requirements/src/scripts/dast_cleanup-requirements.md) to reflect safe parameterized classification-delete strategy.
   - Ensure test tags in docs remain 1:1 with implemented tests.

6. **End-to-end validation**
   - Run targeted lanes first (`04`, `10`, `00`, `06`) to shorten feedback loop.
   - Run [24_run_all_tests_parallel.sh](24_run_all_tests_parallel.sh) to confirm full gate success.
   - Summarize file-by-file changes and residual risk (if any).

## Essential Code Changes (concise)
- Replace this risky pattern in [src/scripts/dast_cleanup.py](src/scripts/dast_cleanup.py): dynamic placeholder interpolation inside SQL text.
- Use this safe shape instead:
  - static SQL string + bound parameter (`transaction_id = ANY(:baseline_tx_ids)`) and pass values via params dict.

- Normalize [tests/py/test_teller_mailcart_client.py](tests/py/test_teller_mailcart_client.py) to one module/class definition; remove duplicated post-`unittest.main()` block causing Ruff `E402/F811` gate failures.
