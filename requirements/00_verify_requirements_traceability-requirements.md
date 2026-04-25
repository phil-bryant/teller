# Verify Requirements Traceability Requirements

## Scope

Applies to `00_verify_requirements_traceability.sh`.

R001  Statement: Run in strict shell mode with temporary working files.
Design: Use `umask 007`, `set -euo pipefail`, and `mktemp` files for set operations.
Tests:
- Verify script exits when required variables are unset.

R005  Statement: Discover and verify all `requirements/**/*-requirements.md` files by default.
Design: Enumerate requirement docs from the `requirements/` directory recursively and verify each discovered `*-requirements.md` doc in one run.
Tests:
- Run with no args and verify every `requirements/*.md` file is included.

R010  Statement: Resolve all source files referenced by each requirements document.
Design: Parse backticked source file paths from requirements content and verify each matching source file for that document.
Tests:
- Add a second source file reference to one requirements doc and verify both are checked.

R015  Statement: Fail clearly when discovered files or mappings are missing.
Design: For each requirements file, fail when no source files are discoverable or when a referenced source file does not exist.
Tests:
- Remove a referenced source file and verify explicit non-zero failure output.
- Provide a requirements file with no discoverable source mapping and verify explicit non-zero failure output.

R020  Statement: Parse requirement IDs from requirement-file start-of-line entries.
Design: Extract IDs matching `R###` with optional `-###` suffix and deduplicate.
Tests:
- Include duplicate IDs in requirements and verify deduped set behavior.

R025  Statement: Parse all `#R` tags from source content.
Design: Scan each line for one or many `#R###` tags with optional `-###` suffix.
Tests:
- Add multiple tags in one source line and verify each is extracted.

R030  Statement: Report missing and extra traceability IDs as set differences.
Design: Use `comm` comparisons against sorted unique ID sets.
Tests:
- Remove one source tag and verify it appears in missing list.
- Add unknown source tag and verify it appears in extra list.

R035  Statement: Exit success only when every requirements-to-source comparison matches.
Design: Return `0` only when all discovered requirements files and their source files have no missing or extra IDs; otherwise return `1`.
Tests:
- Verify all discovered pairs matching returns pass.
- Verify any discovered mismatch returns non-zero.

R040  Statement: Enforce numbered script coverage by numbered requirements docs.
Design: During full-run mode, compare repository `NN_*.sh`/`NN_*.py` scripts against `requirements/NN_*-requirements.md` and fail when any numbered script lacks a matching numbered requirements document.
Tests:
- Add a numbered script without a matching numbered requirements doc and verify explicit failure output.
- Add matching numbered requirements doc and verify coverage pass output.

R045  Statement: Enforce numbered requirements scope alignment with numbered scripts.
Design: For each `requirements/NN_*-requirements.md`, require at least one numbered source reference in Scope that starts with the same `NN_` prefix.
Tests:
- Point a numbered requirements file to a differently numbered script and verify explicit mismatch failure.
- Point it back to matching `NN_` source and verify alignment pass output.

R050  Statement: Discover candidate test files for each requirements document.
Design: Infer test files from requirements path and scoped source conventions, including `tests/sh`, `tests/py`, and Swift tests in `macos-ui/Tests` and `macos-ui/UITests`, while canonicalizing symlinked test paths.
Tests:
- Verify shell-script requirements discover matching `tests/sh/*.bats` candidates.
- Verify Swift requirements discover model/snapshot and UI test lanes without duplicate symlink entries.

R055  Statement: Detect requirement IDs that require UI-lane test coverage.
Design: Parse requirement statement lines and classify IDs with UI-testing intent keywords so those IDs must be covered by UI tests.
Tests:
- Mark one requirement as UI-testing and verify it is treated as UI-lane-required.

R060  Statement: Parse `#R` tags from discovered test files by lane.
Design: Reuse `#R###(-###)*` extraction to build deduplicated ID sets for default and UI lanes.
Tests:
- Include multiple tags per test file line and verify extraction still captures all IDs.

R065  Statement: Enforce at least one tagged test per requirement ID.
Design: For each requirements document, fail when any requirement ID lacks tagged coverage from discovered tests; for UI-classified IDs require presence in the UI lane.
Tests:
- Remove all tagged tests for one ID and verify explicit missing-ID failure output.
- Provide only model-lane tags for a UI-classified ID and verify failure until UI-lane tag is present.
- Provide either model or UI tagged coverage for non-UI IDs and verify pass.

## Changelog

- 2026-04-24: Added numbered script coverage enforcement for `NN_` script/requirements parity.
- 2026-04-24: Added `NN_` requirements-to-source prefix alignment enforcement.
- 2026-04-25: Added requirement-to-test traceability enforcement with contextual Swift UI lane policy.
- 2026-04-20: Updated verifier requirements to require discovery of all `requirements/*.md` files and all referenced source files.
- 2026-04-20: Merged `12_verify_prereq_traceability.sh` and `13_verify_traceability_batch.sh` into `verify_requirements_traceability.sh`.
- 2026-04-19: Initial reverse-engineered requirements for `12_verify_prereq_traceability.sh`.
