---
name: stabilize-parallel-failures
overview: Stabilize the four failing lanes by fixing traceability tagging, aligning pip-tools handling with the new supply-chain model, removing the DAST shell parse hazard, and hardening the flaky macOS UI delete scenario.
todos:
  - id: fix-traceability-r025t02
    content: "Add missing #R025-T02 test tag in tests/sh/t01_run_av_test.bats and verify t04 passes"
    status: completed
  - id: align-piptools-tooling-model
    content: Refactor 03_prepare_supply_chain_integrity.sh + corresponding requirements/test docs to use pip-compile without venv pip-tools install
    status: completed
  - id: remove-dast-process-substitution
    content: Replace parse-breaking process substitution in run_dynamic_security_lane.sh and validate t12
    status: completed
  - id: stabilize-ui-delete-scenario
    content: Harden TransactionClassifierUITests scenario 29 wait/assert behavior and verify t14
    status: completed
  - id: run-targeted-and-full-verification
    content: Execute t02/t04/t12/t14 targeted reruns then full 11_run_all_tests_parallel.sh
    status: completed
isProject: false
---

# Stabilize Parallel Test Failures

## Scope
Address failures in `t02`, `t04`, `t12`, and `t14` from `11_run_all_tests_parallel.sh` with the strategy you selected:
- Keep `pip-tools` as tooling (Homebrew-only), not a runtime venv dependency.
- Include the macOS UI regression fix in this same pass.

## Implementation Plan

1. Fix the single requirements traceability miss (`t04`)
- Update [`/Users/phil/local/src/teller/tests/sh/t01_run_av_test.bats`](/Users/phil/local/src/teller/tests/sh/t01_run_av_test.bats) to add the missing `#R025-T02` tag on the stale-signature refresh test block.
- Re-run the traceability lane and confirm the `numbered-test-tags` check is fully green for [`/Users/phil/local/src/teller/requirements/t01_run_av_test-requirements.md`](/Users/phil/local/src/teller/requirements/t01_run_av_test-requirements.md).

2. Resolve `pip-tools` venv-cruft conflict without weakening policy (`t02`)
- Modify [`/Users/phil/local/src/teller/03_prepare_supply_chain_integrity.sh`](/Users/phil/local/src/teller/03_prepare_supply_chain_integrity.sh):
  - remove fallback `python3 -m pip install pip-tools` in venv,
  - require/use `pip-compile` on PATH (installed by step 01 prerequisites).
- Update requirement doc wording in [`/Users/phil/local/src/teller/requirements/03_prepare_supply_chain_integrity-requirements.md`](/Users/phil/local/src/teller/requirements/03_prepare_supply_chain_integrity-requirements.md) to reflect the `pip-compile` invocation model.
- Update Bats assertions in [`/Users/phil/local/src/teller/tests/sh/03_prepare_supply_chain_integrity.bats`](/Users/phil/local/src/teller/tests/sh/03_prepare_supply_chain_integrity.bats) to match the new command path.
- Keep [`/Users/phil/local/src/teller/tests/t02_run_dependency_freshness_tests.sh`](/Users/phil/local/src/teller/tests/t02_run_dependency_freshness_tests.sh) and [`/Users/phil/local/src/teller/src/scripts/check_dependency_freshness.py`](/Users/phil/local/src/teller/src/scripts/check_dependency_freshness.py) unchanged (gate remains strict).

3. Fix shell parse hazard in DAST lane (`t12`)
- Replace the Bash process-substitution read pattern near the ZAP summary parse in [`/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh) with a POSIX-safe equivalent that avoids `< <(...)`.
- Validate by linting/parsing and re-running `tests/t12_run_dynamic_security_tests.sh`.

4. Harden macOS UI delete scenario (`t14`)
- In [`/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift`](/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift), strengthen scenario 29 (`manageCategoryDelete`) to reduce false negatives under load (longer/conditioned wait and clearer post-delete assertion signal).
- Use isolated reruns (scenario-focused) and then full `t14` to verify stability.

5. End-to-end verification
- Re-run targeted lanes first: `t04`, `t02`, `t12`, `t14`.
- Re-run `./11_run_all_tests_parallel.sh` to confirm the original failure set is cleared.
- If `t14` remains intermittent, add focused diagnostics (status/error text capture and richer assertion logging) before widening scope.

## Validation Sequence
- Fast checks: traceability + dependency freshness + DAST syntax path.
- UI checks: isolated scenario 29, then full smoke profile.
- Final: full parallel suite.

## Expected Outcome
- `t04` passes with complete requirements↔tests tag parity.
- `t02` passes without declaring `pip-tools` as runtime dependency.
- `t12` no longer fails with shell parse error at the ZAP summary block.
- `t14` delete scenario is stable enough to pass in normal runs.
