---
name: always-run-security-freshness-substep
overview: Extend dependency freshness lane t02 to always execute a second freshness check for the security toolchain environment and lockfile, while preserving existing strict gating semantics.
todos:
  - id: update-t02-orchestration
    content: Add always-on security freshness substep and artifact outputs to t02 wrapper
    status: completed
  - id: update-t02-requirements
    content: Add requirement clauses and test IDs for security freshness substep contract
    status: completed
  - id: extend-t02-bats
    content: Update/add Bats tests to verify second invocation, strict flags, and new artifacts
    status: completed
  - id: verify-lane-behavior
    content: Execute t02 Bats and wrapper checks to confirm expected failing/passing semantics
    status: completed
isProject: false
---

# Always-Run Security Freshness Substep in t02

## Goal
Make `tests/t02_run_dependency_freshness_tests.sh` always run a second dependency freshness pass for the security toolchain (`artifacts/venv/security` + `requirements/security/requirements-security.txt`) in addition to the existing project-runtime pass.

## Scope and File Changes
- Update orchestration in [`/Users/phil/local/src/teller/tests/t02_run_dependency_freshness_tests.sh`](/Users/phil/local/src/teller/tests/t02_run_dependency_freshness_tests.sh):
  - Add resolved security interpreter selection (prefer `./artifacts/venv/security/bin/python`, fallback `python3` with usability check).
  - Add a new unconditional substep after the existing runtime freshness run:
    - Invoke `./src/scripts/check_dependency_freshness.py`
    - Pass `--requirements ./requirements/security/requirements-security.txt`
    - Write dedicated artifacts (e.g. `security-toolchain-dependency-freshness.json/.txt`) under the same report dir.
    - Keep strict gates enabled (`--fail-on-any-actionable-outdated`, `--fail-on-direct-outdated`, `--fail-on-venv-cruft`).
- Update requirements in [`/Users/phil/local/src/teller/requirements/t02_run_dependency_freshness_tests-requirements.md`](/Users/phil/local/src/teller/requirements/t02_run_dependency_freshness_tests-requirements.md):
  - Add/extend requirement clauses to explicitly require always-on security-toolchain freshness coverage, interpreter resolution behavior, and output artifact contract.
  - Add corresponding test IDs for Bats traceability.
- Update shell tests in [`/Users/phil/local/src/teller/tests/sh/t02_run_dependency_freshness_tests.bats`](/Users/phil/local/src/teller/tests/sh/t02_run_dependency_freshness_tests.bats):
  - Extend existing "default run" test to assert the second invocation and new report outputs.
  - Add focused tests for interpreter selection/fallback and strict flag propagation on the security substep.

## Behavioral Contract
- `t02` now performs two strict freshness checks every run:
  1. Runtime project environment (`requirements.txt`) - existing behavior.
  2. Security toolchain environment (`requirements/security/requirements-security.txt`) - new always-on behavior.
- Any blocking freshness violation from either pass fails the lane.
- Security-substep outputs are distinct from runtime outputs to keep diagnostics clear.

## Validation
- Run `tests/sh/t02_run_dependency_freshness_tests.bats` to verify orchestration + traceability.
- Run `tests/t02_run_dependency_freshness_tests.sh` once in repo context to confirm both freshness reports are emitted and lane exit semantics are correct.
