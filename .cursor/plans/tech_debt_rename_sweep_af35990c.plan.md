---
name: tech debt rename sweep
overview: Apply a repo-wide naming normalization pass (reclassification→classification and script/path renames), convert the macOS reclassifier plan into traceable requirements docs, and update traceability/test/docs references so the project remains internally consistent.
todos:
  - id: rename-files-and-paths
    content: Rename/move scripts, module files, and `macos` directory to requested target names/locations.
    status: completed
  - id: update-code-references
    content: Update imports, shell invocations, test fixtures, and in-code terminology for broad classification naming.
    status: completed
  - id: migrate-plan-to-requirements
    content: Convert macOS reclassifier plan into `requirements/*-requirements.md` docs mapped to source files and rename existing classification requirement docs.
    status: completed
  - id: repair-traceability
    content: Update traceability source mappings and run/fix `00_verify_requirements_traceability.sh` for all requirement docs.
    status: completed
  - id: docs-and-test-sweep
    content: Update README/requirements/test docs and run targeted tests plus unit-test harness to validate rename integrity.
    status: completed
isProject: false
---

# Tech Debt Rename and Requirements Migration Plan

## Scope And Outcomes
- Standardize naming from `reclassification` to `classification` across code, scripts, requirements, tests, and docs (broad scope as requested).
- Replace the plan artifact at [`/Users/phil/local/src/teller/.cursor/plans/macos_transaction_reclassifier_1e326d42.plan.md`](/Users/phil/local/src/teller/.cursor/plans/macos_transaction_reclassifier_1e326d42.plan.md) with one or more `requirements/*-requirements.md` files aligned to existing conventions.
- Keep requirements traceability green by updating source-path discovery and references used by [`/Users/phil/local/src/teller/00_verify_requirements_traceability.sh`](/Users/phil/local/src/teller/00_verify_requirements_traceability.sh), requirement docs, and `#R...` mappings.

## Planned Changes

### 1) Rename Artifacts And Terminology
- Rename primary files/scripts/modules:
  - [`/Users/phil/local/src/teller/08_capture_teller_token.sh`](/Users/phil/local/src/teller/08_capture_teller_token.sh) -> `08_run_teller-connect-ui.sh`
  - [`/Users/phil/local/src/teller/09_teller_client.py`](/Users/phil/local/src/teller/09_teller_client.py) -> `09_fetch_teller_api_data.py`
  - [`/Users/phil/local/src/teller/10_backfill_statements.py`](/Users/phil/local/src/teller/10_backfill_statements.py) -> `10_backfill_bank_statements.py`
  - [`/Users/phil/local/src/teller/14_run_transaction_classifier.sh`](/Users/phil/local/src/teller/14_run_transaction_classifier.sh) -> `15_run_transaction_classification_macos-ui.sh`
  - [`/Users/phil/local/src/teller/macos`](/Users/phil/local/src/teller/macos) -> `macos-ui`
  - [`/Users/phil/local/src/teller/teller/teller_reclassification_api.py`](/Users/phil/local/src/teller/teller/teller_reclassification_api.py) -> classification name (file/module + symbol usage updates)
  - [`/Users/phil/local/src/teller/11_transaction_reclassification_api.py`](/Users/phil/local/src/teller/11_transaction_reclassification_api.py) and [`/Users/phil/local/src/teller/12_verify_reclassification_persistence.sh`](/Users/phil/local/src/teller/12_verify_reclassification_persistence.sh) -> classification names
- Apply broad textual renames (`reclassification` -> `classification`) in Python/Swift/shell/docs/tests with careful review to avoid changing unrelated established domain terms.

### 2) Move Token Server Module Into Package
- Move [`/Users/phil/local/src/teller/teller_connect_token_server.py`](/Users/phil/local/src/teller/teller_connect_token_server.py) -> [`/Users/phil/local/src/teller/teller/teller_connect_token_server.py`](/Users/phil/local/src/teller/teller/teller_connect_token_server.py).
- Update imports and runtime script references from root-module usage to package-qualified usage.
- Update shell test fixtures and any path assumptions in [`/Users/phil/local/src/teller/tests/sh/08_capture_teller_token.bats`](/Users/phil/local/src/teller/tests/sh/08_capture_teller_token.bats) and related helpers.

### 3) Convert macOS Plan Into Requirements Docs
- Decompose plan content from [`/Users/phil/local/src/teller/.cursor/plans/macos_transaction_reclassifier_1e326d42.plan.md`](/Users/phil/local/src/teller/.cursor/plans/macos_transaction_reclassifier_1e326d42.plan.md) into requirements documents that map to concrete `.py/.sh/.swift` sources.
- Update/rename existing classification-related requirement docs:
  - [`/Users/phil/local/src/teller/requirements/teller_reclassification_api-requirements.md`](/Users/phil/local/src/teller/requirements/teller_reclassification_api-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/11_transaction_reclassification_api-requirements.md`](/Users/phil/local/src/teller/requirements/11_transaction_reclassification_api-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/12_verify_reclassification_persistence-requirements.md`](/Users/phil/local/src/teller/requirements/12_verify_reclassification_persistence-requirements.md)
- Add missing Swift-side requirements docs for renamed `macos-ui` source files (split by primary source file so each doc has a clear `## Scope` and `R###` set).
- Remove or archive the plan markdown after requirements are fully represented and linked from project docs.

### 4) Update Traceability Pipeline For New Names
- Update references and usage/help text in [`/Users/phil/local/src/teller/00_verify_requirements_traceability.sh`](/Users/phil/local/src/teller/00_verify_requirements_traceability.sh) where old requirement/source names are embedded.
- Ensure all renamed requirement docs still expose valid `## Scope` backticked source paths so auto-discovery works.
- Update requirement IDs / `#R...` tags only where source moves or file rewrites require it; preserve existing IDs where possible to keep diff noise low.

### 5) Sweep Dependent References
- Update root docs and module docs:
  - [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md)
  - [`/Users/phil/local/src/teller/macos/README.md`](/Users/phil/local/src/teller/macos/README.md) (renamed path/content)
  - [`/Users/phil/local/src/teller/requirements/*.md`](/Users/phil/local/src/teller/requirements)
- Update shell/python/swift tests and test docs under:
  - [`/Users/phil/local/src/teller/tests/sh`](/Users/phil/local/src/teller/tests/sh)
  - [`/Users/phil/local/src/teller/tests/py`](/Users/phil/local/src/teller/tests/py)
  - [`/Users/phil/local/src/teller/tests/swift`](/Users/phil/local/src/teller/tests/swift)
- Update `.gitignore` and any package metadata paths affected by `macos` -> `macos-ui` and script/module renames.

## Verification Plan
- Run targeted grep checks for old names to confirm no stale references remain (`reclassification`, old script names, old `macos/` path, old token-server location).
- Run [`/Users/phil/local/src/teller/00_verify_requirements_traceability.sh`](/Users/phil/local/src/teller/00_verify_requirements_traceability.sh) in all-requirements mode and fix any missing/extra `#R` tags.
- Run shell and python unit tests most affected by renames (especially `tests/sh/*` for renamed scripts and `tests/py/*classification*` for API module rename).
- Run `04_run_unit_tests.sh` flow after `macos-ui` migration to verify Swift test path updates.

## Execution Order
- Perform filesystem renames/moves first.
- Apply code/import/path reference updates second.
- Convert requirements and traceability mappings third.
- Finish with docs/tests and full verification sweep.