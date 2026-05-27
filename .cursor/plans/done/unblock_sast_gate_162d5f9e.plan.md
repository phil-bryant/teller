---
name: Unblock SAST gate
overview: Remediate the concrete causes behind the current Bandit, Ruff, detect-secrets, and gitleaks findings. Keep security checks strict while removing scanner self-noise by fixing code and scan flow.
todos:
  - id: remediate-ruff-violations
    content: Fix the 11 concrete Ruff violations in source files rather than changing Ruff severity policy
    status: completed
  - id: remediate-bandit-findings
    content: Harden teller_classification_api token retrieval and constants to clear Bandit findings via code changes
    status: completed
  - id: break-scanner-feedback-loop
    content: Prevent secret scanners from scanning generated scanner artifacts and caches while preserving strict source scanning
    status: completed
  - id: update-sast-tests
    content: Update Bats coverage for root-cause remediation behavior and strict gate expectations
    status: completed
  - id: document-policy
    content: Update SAST requirements docs to reflect concrete remediations and scan ordering rationale
    status: completed
isProject: false
---

# Unblock SAST Gate Failures

## What is failing now
- Current SAST run fails with:
  - `bandit_total = 5`,
  - `ruff_total = 11`,
  - `detect_secrets_findings = 1`,
  - `gitleaks_findings = 1`.
- Root causes identified:
  - Ruff findings are concrete style/code hygiene issues across existing Python modules.
  - Bandit findings come from token retrieval and token-named literals in [`teller/teller_classification_api.py`](/Users/phil/local/src/teller/teller/teller_classification_api.py).
  - detect-secrets hit is from generated cache content (`.ruff_cache/CACHEDIR.TAG` hash).
  - gitleaks is scanning scanner output artifacts under `.security-reports` and re-flagging hashed_secret values from prior reports.

## Implementation plan
- Remediate all 11 Ruff findings in code (no gating-policy reduction), including files reported by Ruff:
  - [`13_backfill_bank_statements.py`](/Users/phil/local/src/teller/13_backfill_bank_statements.py),
  - [`teller/teller_account.py`](/Users/phil/local/src/teller/teller/teller_account.py),
  - [`teller/teller_account_balances.py`](/Users/phil/local/src/teller/teller/teller_account_balances.py),
  - [`teller/teller_account_details.py`](/Users/phil/local/src/teller/teller/teller_account_details.py),
  - [`teller/teller_account_details_links.py`](/Users/phil/local/src/teller/teller/teller_account_details_links.py),
  - [`teller/teller_enums.py`](/Users/phil/local/src/teller/teller/teller_enums.py),
  - [`teller/teller_identity_address.py`](/Users/phil/local/src/teller/teller/teller_identity_address.py),
  - [`teller/teller_object.py`](/Users/phil/local/src/teller/teller/teller_object.py),
  - [`teller/teller_transaction.py`](/Users/phil/local/src/teller/teller/teller_transaction.py).
- Remediate Bandit findings in [`teller/teller_classification_api.py`](/Users/phil/local/src/teller/teller/teller_classification_api.py):
  - Use explicit executable resolution (absolute path) for `1psa` invocation.
  - Refactor token/header constants and retrieval flow to avoid hardcoded-secret heuristics while preserving behavior.
  - Keep subprocess usage constrained to fixed argv and strict error handling.
- Eliminate scanner feedback-loop findings in [`06_run_static_security_tests.sh`](/Users/phil/local/src/teller/06_run_static_security_tests.sh):
  - Ensure scanners do not scan generated scanner outputs in `.security-reports`.
  - Ensure cache/runtime artifacts (for example `.ruff_cache`) are cleaned or excluded before secret scans.
  - Preserve strict scanning of source/config inputs.
- Update test coverage in [`tests/sh/06_run_static_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/06_run_static_security_tests.bats):
  - Add regression tests that scanner output artifacts do not self-trigger gitleaks/detect-secrets.
  - Keep strict gate-fail tests for real findings.
- Update SAST documentation in [`requirements/06_run_static_security_tests-requirements.md`](/Users/phil/local/src/teller/requirements/06_run_static_security_tests-requirements.md) with root-cause rationale and expected scanner sequencing.

## Validation
- Run shell tests for SAST script behavior in [`tests/sh/06_run_static_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/06_run_static_security_tests.bats).
- Re-run `./06_run_static_security_tests.sh` and verify summary target:
  - `bandit_total = 0`,
  - `ruff_total = 0`,
  - `detect_secrets_findings = 0`,
  - `gitleaks_findings = 0`,
  - `high_critical_total = 0` with strict gate unchanged.