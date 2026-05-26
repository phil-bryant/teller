---
name: remove-23-run-ui-refs
overview: Remove the deprecated `23_run_classification_macos-ui.sh` path and standardize all active scripts/docs/tests on the `24` launcher only.
todos:
  - id: delete-23-wrapper
    content: Remove deprecated 23 launcher script and any direct script-level references in active code paths.
    status: completed
  - id: migrate-traceability-tests
    content: Rename/rework requirements and bats coverage from 23 launcher wrapper to canonical 24 launcher.
    status: completed
  - id: update-readme-refs
    content: Replace README references to 23 launcher with 24 launcher.
    status: completed
  - id: validate-no-active-23-refs
    content: Run traceability/tests + final search to confirm active scope has no remaining 23 launcher references.
    status: completed
isProject: false
---

# Remove 23 Run UI References

## Goal
Make the repository use only `24_run_classification_macos-ui.sh` for the macOS UI launcher and eliminate active references to `23_run_classification_macos-ui.sh`.

## Planned changes
- Delete the deprecated wrapper script [23_run_classification_macos-ui.sh](/Users/phil/local/src/teller/23_run_classification_macos-ui.sh).
- Migrate wrapper-specific traceability artifacts to the canonical script:
  - Replace [requirements/23_run_classification_macos-ui-requirements.md](/Users/phil/local/src/teller/requirements/23_run_classification_macos-ui-requirements.md) with a `24`-named requirements file that applies to [24_run_classification_macos-ui.sh](/Users/phil/local/src/teller/24_run_classification_macos-ui.sh).
  - Replace [tests/sh/23_run_classification_macos-ui.bats](/Users/phil/local/src/teller/tests/sh/23_run_classification_macos-ui.bats) with a `24`-named bats test file validating the canonical launcher behavior (and remove all `23` path assertions).
- Update all active documentation references in [README.md](/Users/phil/local/src/teller/README.md) from `23_run_classification_macos-ui.sh` to `24_run_classification_macos-ui.sh`.

## Validation
- Run targeted shell tests for the launcher bats file.
- Run requirements traceability to confirm no orphaned `23` requirements/script references remain and `24` mapping is consistent.
- Run a final repo search for `23_run_classification_macos-ui.sh` (excluding generated artifacts and plans per chosen scope) to verify cleanup completeness.