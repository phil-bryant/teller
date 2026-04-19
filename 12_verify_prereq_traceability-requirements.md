# Verify Prereq Traceability Requirements

## Scope

Applies to `12_verify_prereq_traceability.sh`.

R001  Statement: Run in strict shell mode with temporary working files.
Design: Use `umask 007`, `set -euo pipefail`, and `mktemp` files for set operations.
Tests:
- Verify script exits when required variables are unset.

R005  Statement: Accept requirements and script paths as positional inputs.
Design: Default to prereq pair when args are not provided.
Tests:
- Run with no args and verify default files are targeted.
- Run with custom args and verify custom files are targeted.

R010  Statement: Fail clearly when target files are missing.
Design: Check both files before parsing and print explicit error lines.
Tests:
- Pass non-existent requirements path and verify non-zero exit.

R015  Statement: Parse requirement IDs from requirement-file start-of-line entries.
Design: Extract IDs matching `R###` with optional `-###` suffix and deduplicate.
Tests:
- Include duplicate IDs in requirements and verify deduped set behavior.

R020  Statement: Parse all `#R` tags from script content.
Design: Scan each line for one or many `#R###` tags with optional `-###` suffix.
Tests:
- Add multiple tags in one script line and verify each is extracted.

R025  Statement: Report missing and extra traceability IDs as set differences.
Design: Use `comm` comparisons against sorted unique ID sets.
Tests:
- Remove one script tag and verify it appears in missing list.
- Add unknown script tag and verify it appears in extra list.

R030  Statement: Exit success only on exact bidirectional ID match.
Design: Return `0` only when no missing or extra IDs; otherwise return `1`.
Tests:
- Verify exact match returns pass.
- Verify any mismatch returns non-zero.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `12_verify_prereq_traceability.sh`.
