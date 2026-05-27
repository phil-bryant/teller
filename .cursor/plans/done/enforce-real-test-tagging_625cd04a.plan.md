---
name: enforce-real-test-tagging
overview: Close the traceability loophole by requiring numbered test tags to live inside real test blocks, and update requirements/tests so header anchor bundles fail as intended.
todos:
  - id: define-policy
    content: Specify language-aware parsing rules for valid numbered tag locations in Bats/Python/Swift tests and document failure semantics.
    status: completed
  - id: implement-checker
    content: Add strict test-block scoped numbered-tag extraction/validation in 00_run_requirements_traceability_tests.sh and wire it into R090 checks.
    status: completed
  - id: update-spec-and-tests
    content: Update 00 requirements and bats fixtures to assert header-anchor cheating fails and in-test tags pass.
    status: completed
  - id: verify
    content: Run the traceability bats suite for 00 and ensure strict mode catches the teller_object-style cheat.
    status: completed
isProject: false
---

# Enforce Numbered Tags In Real Tests

## Goal
Ensure `#Rxxx-T##` traceability tags are only counted when they are attached to executable test cases, not header-level anchor bundles.

## Confirmed Gap
Current logic in [`/Users/phil/local/src/teller/00_run_requirements_traceability_tests.sh`](/Users/phil/local/src/teller/00_run_requirements_traceability_tests.sh) extracts numbered tags from entire files (`extract_numbered_test_ids`) and does not scope them to test bodies. This allows header anchor blocks like those in [`/Users/phil/local/src/teller/tests/py/test_teller_object.py`](/Users/phil/local/src/teller/tests/py/test_teller_object.py) to satisfy R090 without tagging actual test logic.

## Implementation Plan
1. **Add language-aware “test-block scoped” numbered-tag extraction**
   - In [`/Users/phil/local/src/teller/00_run_requirements_traceability_tests.sh`](/Users/phil/local/src/teller/00_run_requirements_traceability_tests.sh), replace or augment `extract_numbered_test_ids` so it only emits tags found inside recognized test blocks:
     - Bats: lines inside `@test "..." { ... }`
     - Python `unittest`/pytest style: inside `def test_*` methods/functions
     - Swift XCTest: inside functions named `test*`
   - Keep current fallback behavior only for unknown test file types if needed, but fail strict mode when no valid in-test tags exist for required IDs.

2. **Detect and fail header-anchor anti-pattern for numbered tags**
   - Add a dedicated anti-cheat check for test files (parallel to source header-bundle anti-cheat), focused on numbered tags in pre-test header regions.
   - Emit explicit failure messaging that points to the file and offending line(s), e.g. “numbered tags must be inside test blocks.”

3. **Integrate new extraction into R090 1:1 checks**
   - Update `collect_numbered_test_ids_from_list` path in [`/Users/phil/local/src/teller/00_run_requirements_traceability_tests.sh`](/Users/phil/local/src/teller/00_run_requirements_traceability_tests.sh) to consume scoped in-test tags.
   - Preserve existing R090 missing/extra diagnostics and requirements-bullet validation.

4. **Update requirements to codify stricter policy**
   - In [`/Users/phil/local/src/teller/requirements/00_run_requirements_traceability_tests-requirements.md`](/Users/phil/local/src/teller/requirements/00_run_requirements_traceability_tests-requirements.md), add/adjust requirement text and tests so policy explicitly states numbered tags must be in executable test code blocks.

5. **Strengthen fixture coverage**
   - In [`/Users/phil/local/src/teller/tests/sh/00_run_requirements_traceability_tests.bats`](/Users/phil/local/src/teller/tests/sh/00_run_requirements_traceability_tests.bats):
     - Add a failing fixture mirroring the `teller_object` cheat pattern (header-only numbered anchors).
     - Add a passing fixture with same IDs moved into actual test bodies.
     - Ensure assertions check for the new anti-cheat/placement failure text.

## Validation
- Run targeted suite: [`/Users/phil/local/src/teller/tests/sh/00_run_requirements_traceability_tests.bats`](/Users/phil/local/src/teller/tests/sh/00_run_requirements_traceability_tests.bats).
- Run script-level check for the affected requirement doc pairing to confirm the header-anchor case now fails and properly tagged test bodies pass.

## Expected Outcome
`requirements/teller/teller_object-requirements.md` can no longer be “satisfied” by header-only `#Rxxx-T##` anchors; tags must be colocated with real test code, and `00` fails when they are not.