---
name: fix-traceability-23-27
overview: Restore full traceability compliance by converting script 23 from requirements-only to enforceable traceability and adding missing requirements coverage for scripts 26 and 27.
todos:
  - id: convert-23-from-requirements-only
    content: Convert script 23 requirements/test/source into enforceable full traceability with R### and numbered test tags
    status: completed
  - id: add-26-requirements-traceability
    content: Create requirements doc and add source/test traceability tags for 26_report_quality_trends
    status: completed
  - id: add-27-requirements-traceability
    content: Create requirements doc and add source/test traceability tags for 27_validate_quality_target
    status: completed
  - id: run-traceability-suite
    content: Run full traceability script and confirm all checks pass
    status: completed
isProject: false
---

# Fix Traceability for Scripts 23, 26, and 27

## Goal
Make `./00_run_requirements_traceability_tests.sh` pass by resolving the two failing checks:
- missing numbered requirements docs for `26` and `27`
- repository software coverage gap for `23_run_classification_macos-ui.sh`

## Confirmed Root Causes
- [`requirements/23_run_classification_macos-ui-requirements.md`](requirements/23_run_classification_macos-ui-requirements.md) is currently marked `Requirements-only mode: true`, so the file is excluded from repository coverage in [`00_run_requirements_traceability_tests.sh`](00_run_requirements_traceability_tests.sh) (`verify_repository_source_requirements_coverage` skips requirements-only docs).
- `26_report_quality_trends.sh` and `27_validate_quality_target.sh` have tests but no numbered requirements docs under `requirements/26_*-requirements.md` and `requirements/27_*-requirements.md`.

## Implementation Plan

1. Convert script 23 to full traceability
- Update [`requirements/23_run_classification_macos-ui-requirements.md`](requirements/23_run_classification_macos-ui-requirements.md):
  - remove `Requirements-only mode: true`
  - add concrete `R###` requirements describing strict-mode behavior, deprecation notice, and `exec` handoff to script 24
  - add numbered `Tests:` bullets (`Rxxx-T##`) aligned to the existing Bats test
- Update [`23_run_classification_macos-ui.sh`](23_run_classification_macos-ui.sh): add scoped `#Rxxx:` tags adjacent to implemented behavior.
- Update [`tests/sh/23_run_classification_macos-ui.bats`](tests/sh/23_run_classification_macos-ui.bats): add matching `#Rxxx-T##` tags in test blocks and expand coverage if needed to satisfy all new requirement IDs.

2. Add requirements doc for script 26
- Create [`requirements/26_report_quality_trends-requirements.md`](requirements/26_report_quality_trends-requirements.md) with:
  - `## Scope` referencing `26_report_quality_trends.sh`
  - `R###` requirements for repo-root resolution, missing-trend failure, JSON rendering of trend metrics, and PASS/WARN/FAIL status output
  - numbered `Tests:` bullets matching existing Bats assertions
- Update [`26_report_quality_trends.sh`](26_report_quality_trends.sh) with scoped `#Rxxx:` tags.
- Update [`tests/sh/26_report_quality_trends.bats`](tests/sh/26_report_quality_trends.bats) with `#Rxxx-T##` tags aligned to requirement bullets.

3. Add requirements doc for script 27
- Create [`requirements/27_validate_quality_target-requirements.md`](requirements/27_validate_quality_target-requirements.md) with:
  - `## Scope` referencing `27_validate_quality_target.sh`
  - `R###` requirements for missing-history failure, 21-day filtering logic, minimum span check, consecutive-week validation, and PASS output on success
  - numbered `Tests:` bullets mapped to Bats coverage
- Update [`27_validate_quality_target.sh`](27_validate_quality_target.sh) with scoped `#Rxxx:` tags.
- Update [`tests/sh/27_validate_quality_target.bats`](tests/sh/27_validate_quality_target.bats) with `#Rxxx-T##` tags aligned to requirement bullets.

4. Validate end-to-end
- Run `./00_run_requirements_traceability_tests.sh` and verify:
  - numbered requirements coverage passes for `26` and `27`
  - repository software coverage no longer flags `23_run_classification_macos-ui.sh`
  - no new numbered-tag or source/test traceability regressions are introduced.

## Notes on consistency
- Mirror formatting and conventions used by existing numbered docs such as [`requirements/24_run_classification_macos-ui-requirements.md`](requirements/24_run_classification_macos-ui-requirements.md) and [`requirements/25_run_all_tests_parallel-requirements.md`](requirements/25_run_all_tests_parallel-requirements.md).
- Keep requirement/test IDs compact and script-local to avoid cross-file ID collisions during future renumbering.