# Verify Prereq Traceability Requirements

## Scope

Applies to `00_verify_requirements_traceability.sh`.

R001  Statement: Run in strict shell mode with temporary working files.
Design: Use `umask 007`, `set -euo pipefail`, and `mktemp` files for set operations.
Tests:
- Verify script exits when required variables are unset.

R005  Statement: Discover and verify all `requirements/*.md` files by default.
Design: Enumerate requirement docs from the `requirements/` directory and verify each discovered doc in one run.
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

## Changelog

- 2026-04-20: Updated verifier requirements to require discovery of all `requirements/*.md` files and all referenced source files.
- 2026-04-20: Merged `12_verify_prereq_traceability.sh` and `13_verify_traceability_batch.sh` into `verify_requirements_traceability.sh`.
- 2026-04-19: Initial reverse-engineered requirements for `12_verify_prereq_traceability.sh`.
