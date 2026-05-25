# Verify Requirements Traceability Requirements

## Scope

Applies to `00_run_requirements_traceability_tests.sh` and requirement/test traceability policy in this repository.

R001  Statement: Run in strict shell mode with temporary working files.
Design: Use `umask 007`, `set -euo pipefail`, and `mktemp` files for set operations.
Tests:
- R001-T01: Verify script exits when required variables are unset.

R005  Statement: Discover and verify all `requirements/**/*-requirements.md` files by default.
Design: Enumerate requirement docs from the `requirements/` directory recursively and verify each discovered `*-requirements.md` doc in one run.
Tests:
- R005-T01: Run with no args and verify all discovered requirements documents are visited.

R010  Statement: Resolve source files referenced by each requirements document.
Design: Parse backticked source file paths from requirements scope/design text and verify each matching source file for that document.
Tests:
- R010-T01: Add a second source file reference to one requirements doc and verify both are checked.

R015  Statement: Fail clearly when discovered files or mappings are missing.
Design: For each requirements file, fail when no source files are discoverable or when a referenced source file does not exist unless requirements-only mode is explicitly declared.
Tests:
- R015-T01: Remove a referenced source file and verify explicit non-zero failure output.
- R015-T02: Provide a requirements file with no discoverable source mapping and verify explicit non-zero failure output.

R020  Statement: Parse requirement IDs from requirement-file start-of-line entries.
Design: Extract IDs matching `R###` with optional `-###` suffix and deduplicate.
Tests:
- R020-T01: Include duplicate IDs in requirements and verify deduped set behavior.

R025  Statement: Parse all `#R` tags from source content.
Design: Scan each line for one or many `#R###` tags with optional `-###` suffix.
Tests:
- R025-T01: Add multiple tags in one source line and verify each is extracted.

R030  Statement: Report missing and extra traceability IDs as set differences.
Design: Use `comm` comparisons against sorted unique ID sets.
Tests:
- R030-T01: Remove one source tag and verify it appears in missing list.
- R030-T02: Add unknown source tag and verify it appears in extra list.

R035  Statement: Exit success only when every enforceable traceability comparison matches.
Design: Return `0` only when all discovered requirements files and their source/test checks have no missing or extra IDs; otherwise return `1`.
Tests:
- R035-T01: Verify all discovered pairs matching returns pass.
- R035-T02: Verify any discovered mismatch returns non-zero.

R040  Statement: Enforce numbered script coverage by numbered requirements docs.
Design: During full-run mode, compare repository `NN_*.sh`/`NN_*.py` scripts against `requirements/NN_*-requirements.md` and fail when any numbered script lacks a matching numbered requirements document.
Tests:
- R040-T01: Add a numbered script without a matching numbered requirements doc and verify explicit failure output.
- R040-T02: Add matching numbered requirements doc and verify coverage pass output.

R045  Statement: Enforce numbered requirements scope alignment with numbered scripts.
Design: For each `requirements/NN_*-requirements.md`, require at least one numbered source reference in Scope that starts with the same `NN_` prefix.
Tests:
- R045-T01: Point a numbered requirements file to a differently numbered script and verify explicit mismatch failure.
- R045-T02: Point it back to matching `NN_` source and verify alignment pass output.

R050  Statement: Discover candidate test files for each requirements document.
Design: Infer test files from requirements path and scoped source conventions, including `tests/sh`, `tests/py`, Swift tests in `macos-ui/Tests` and `macos-ui/UITests`, plus SQL pgTAP path candidates under `tests/sql`, while canonicalizing symlinked test paths.
Tests:
- R050-T01: Verify shell-script requirements discover matching `tests/sh/*.bats` candidates.
- R050-T02: Verify Swift requirements discover model/snapshot and UI test lanes without duplicate symlink entries.
- R050-T03: Verify SQL requirements discover `tests/sql/*.sql` and `tests/sql/test_*.sql` candidates when present.

R055  Statement: Detect requirement IDs that require UI-lane test coverage.
Design: Parse requirement statement lines and classify IDs with UI-testing intent keywords so those IDs must be covered by UI tests.
Tests:
- R055-T01: Mark one requirement as UI-testing and verify it is treated as UI-lane-required.

R060  Statement: Parse `#R` tags from discovered test files by lane.
Design: Reuse `#R###(-###)*` extraction to build deduplicated ID sets for default and UI lanes.
Tests:
- R060-T01: Include multiple tags per test file line and verify extraction still captures all IDs.

R065  Statement: Enforce at least one tagged test per requirement ID.
Design: For each requirements document, fail when any requirement ID lacks tagged coverage from discovered tests; for UI-classified IDs require presence in the UI lane.
Tests:
- R065-T01: Remove all tagged tests for one ID and verify explicit missing-ID failure output.
- R065-T02: Provide only model-lane tags for a UI-classified ID and verify failure until UI-lane tag is present.
- R065-T03: Provide either model or UI tagged coverage for non-UI IDs and verify pass.

R070  Statement: Reject anti-cheat header bundles and require scoped source comments.
Design: Fail when source files use bundled top-of-file `#R###` sets and require scoped implementation comments in the form `#R###:` so each requirement ID is anchored to a concrete code block.
Tests:
- R070-T01: Provide bundled header tags near the top of file and verify explicit anti-cheat failure output.
- R070-T02: Provide unscoped `#R###` tags and verify scoped-comment failure output.
- R070-T03: Provide scoped `#R###:` comments and verify pass output.

R075  Statement: Support explicit requirements-only mode for pre-implementation documents.
Design: If a requirements file declares `Requirements-only mode: true` in `## Scope`, skip source and test traceability checks for that file and report a pass-with-skip status.
Tests:
- R075-T01: Create a requirements-only doc with no source mappings and verify the verifier skips it successfully.
- R075-T02: Remove the requirements-only declaration and verify missing-source failure resumes.

R080  Statement: Enforce numbered script test coverage in Teller full-run mode.
Design: During no-argument full-run mode, require every repository `NN_*.sh` and `NN_*.py` script to have a matching `tests/sh/NN_*.bats` companion. Operators may temporarily disable this with `STRICT_TRACEABILITY_FULL_COVERAGE=false`.
Tests:
- R080-T01: Add a numbered script without a matching `tests/sh/NN_*.bats` and verify explicit failure output.
- R080-T02: Add the matching shell test and verify coverage pass output.

R085  Statement: Auto-detect repository software files that are not covered by any enforceable requirements document.
Design: During no-argument full-run mode, discover repository software sources (for example `.sh`, `.py`, `.swift`, `.sql`, and similar code files outside `requirements/` and tests directories) and fail when any discovered file is not mapped from at least one enforceable `requirements/**/*-requirements.md` Scope source reference. Operators may temporarily disable this with `STRICT_TRACEABILITY_FULL_COVERAGE=false`.
Tests:
- R085-T01: Add an unreferenced software file to a fixture repo and verify explicit full-run failure output naming the uncovered file.
- R085-T02: Add that file to a requirements Scope mapping and verify full-run coverage pass output.

R090  Statement: Enforce 1:1 numbered test-tag traceability (`Rxxx-T##` in requirements vs `#Rxxx-T##` in tests) for enforceable documents.
Design: Parse numbered test bullets under each requirements `Tests:` section and compare them as an exact set against discovered `#Rxxx-T##` tags in discovered tests, scoped to requirement IDs in that document. Fail when any requirement ID lacks a numbered `Rxxx-T##` entry in the requirements doc, when any numbered requirement test ID is missing in tests, and when any numbered test tag exists in tests without a corresponding requirements numbered bullet. Also fail when `Tests:` bullets are malformed (for example, unnumbered bullets that should be `Rxxx-T##:`). This check runs alongside the existing `#R` coverage check (R065) and is skipped for requirements-only docs. Operators may temporarily disable this with `STRICT_TRACEABILITY_NUMBERED_TAGS=false`.
Tests:
- R090-T01: Provide a requirements numbered test ID with no matching `#Rxxx-T##` in tests and verify explicit "missing in tests" failure output.
- R090-T02: Provide a `#Rxxx-T##` in tests with no matching requirements numbered test bullet and verify explicit "missing in requirements" failure output.
- R090-T03: Provide both mismatch directions in one fixture and verify both failure sections are printed.
- R090-T04: Provide malformed `Tests:` bullets (missing `Rxxx-T##:` prefix) and verify explicit malformed-bullet failure output.
- R090-T05: Verify that a requirements-only doc skips the numbered-tag check.
- R090-T06: Omit all numbered `Rxxx-T##` entries for a requirement ID and verify explicit missing-numbered-requirements failure output.

## Changelog

- 2026-05-16: Strengthened R090 to require 1:1 numbered traceability between requirements `Rxxx-T##` bullets and discovered test `#Rxxx-T##` tags, including malformed-bullet rejection.
- 2026-05-16: Added requirements-only mode support for staged docs (R075).
- 2026-05-16: Added numbered script test coverage enforcement for Teller stack scripts (R080).
- 2026-05-16: Added repository software-to-requirements coverage completeness checks (R085).
- 2026-04-25: Added requirement-to-test traceability enforcement with contextual Swift UI lane policy.
- 2026-05-15: Added anti-cheat and scoped source comment enforcement for requirement IDs.
- 2026-04-24: Added numbered script coverage enforcement for `NN_` script/requirements parity.
- 2026-04-24: Added `NN_` requirements-to-source prefix alignment enforcement.
