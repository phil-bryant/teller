---
name: binary-integrity-gate
overview: Add a strict binary integrity/freshness gate for core runtime and scanner toolchain commands, and wire it into the dependency freshness lane with artifacts and tests.
todos:
  - id: add-binary-integrity-script
    content: Create check_binary_integrity.py with path resolution, version/hash collection, policy evaluation, and strict exit gates.
    status: completed
  - id: add-policy-file
    content: Add binary-integrity policy JSON for maximal binary list with required/optional and version/hash constraints.
    status: completed
  - id: wire-lane
    content: Integrate binary integrity check into t02 dependency freshness lane and emit artifacts.
    status: completed
  - id: add-tests
    content: Add unit + bats coverage for invocation and failure semantics.
    status: completed
  - id: update-requirements-docs
    content: Update requirements traceability docs to cover binary integrity gate behavior.
    status: completed
isProject: false
---

# Add Binary Integrity Gate

## Goal
Implement a dedicated integrity/freshness check for key binaries (core + scanner toolchain) and run it in the dependency freshness lane, producing JSON/text artifacts and failing on policy violations.

## Scope (maximal list)
- Core/runtime commands: `python3`, `psql`, `sqlite3`, `op` (or `1psa` wrapper), `curl`, `openssl`, `git`.
- Security/scanner commands: `semgrep`, `bandit`, `pip-audit`, `detect-secrets`, `gitleaks`, `shellcheck`, `swiftlint`, `schemathesis`, `ZAP.sh`.
- Modeled as required/optional entries in policy (to avoid false failures where platform-specific tools are legitimately absent).

## Implementation approach
- Add a new checker script to keep responsibilities separated from Python package freshness:
  - New file: [`/Users/phil/local/src/teller/src/scripts/check_binary_integrity.py`](/Users/phil/local/src/teller/src/scripts/check_binary_integrity.py)
  - Responsibilities:
    - Resolve executable path (from explicit path override or `PATH`).
    - Collect version string (command-specific probe args).
    - Compute SHA256 of executable file bytes.
    - Evaluate policy constraints:
      - `required` boolean
      - `min_version` (when parseable)
      - `allowed_sha256` list
    - Emit report with per-binary status (`ok`, `missing`, `version_stale`, `hash_mismatch`, `unknown_version_parse`).
    - Support strict failure flags (e.g. `--fail-on-missing-required`, `--fail-on-version`, `--fail-on-hash`).
- Add policy configuration with explicit command definitions:
  - New file: [`/Users/phil/local/src/teller/config/security/binary-integrity-policy.json`](/Users/phil/local/src/teller/config/security/binary-integrity-policy.json)
  - Include probe command/args and parse regex per binary.
  - Mark scanner tools that may be environment-specific as optional by default unless explicitly required.
- Wire into dependency freshness lane:
  - Update [`/Users/phil/local/src/teller/tests/t02_run_dependency_freshness_tests.sh`](/Users/phil/local/src/teller/tests/t02_run_dependency_freshness_tests.sh)
  - Run new checker after dependency freshness reports.
  - Output artifacts:
    - `artifacts/security/binary-integrity.json`
    - `artifacts/security/binary-integrity.txt`
  - Keep gate strict by default for required binaries and enabled checks.
- Add/extend tests:
  - New Python unit tests for checker behavior (hash mismatch/version parse/missing required/optional handling).
  - Extend existing lane tests in [`/Users/phil/local/src/teller/tests/sh/t02_run_dependency_freshness_tests.bats`](/Users/phil/local/src/teller/tests/sh/t02_run_dependency_freshness_tests.bats) to assert invocation and strict flags.
- Requirements traceability/docs:
  - Add/update requirements doc for new binary-integrity requirements and gate semantics:
    - [`/Users/phil/local/src/teller/requirements/src/scripts/check_dependency_freshness-requirements.md`](/Users/phil/local/src/teller/requirements/src/scripts/check_dependency_freshness-requirements.md)
    - (or add a sibling requirements file for the new script if preferred by repo convention).

## Design notes
- Preserve current dependency freshness semantics in [`/Users/phil/local/src/teller/src/scripts/check_dependency_freshness.py`](/Users/phil/local/src/teller/src/scripts/check_dependency_freshness.py); do not mix package freshness and binary integrity logic.
- Keep policy data-driven so future binaries can be added without code changes.
- Ensure text report is operator-friendly while JSON remains stable for CI parsing.

## Validation plan
- Run targeted unit tests for the new checker.
- Run `tests/sh/t02_run_dependency_freshness_tests.bats` and confirm strict gate args and artifacts.
- Verify that failure modes are explicit and actionable (which binary failed and why).
