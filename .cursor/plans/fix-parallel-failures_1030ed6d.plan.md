---
name: fix-parallel-failures
overview: Unblock the failing parallel checks by fixing root causes in fuzz, persistence verification, macOS UI automation build config, and SAST findings while preserving strict quality/security gates.
todos:
  - id: strict-fuzz
    content: Raise property-test example budgets and handle finite strategy cases while preserving strict fuzz gate behavior.
    status: completed
  - id: persistence-http-health
    content: Fix protocol/readiness mismatch in classification persistence verification script and improve failure diagnostics.
    status: completed
  - id: xcode-target-sync
    content: Add LocalClassifierTLS.swift to UITest host target in Xcode project and validate macOS UI lane build.
    status: completed
  - id: sast-blockers
    content: Remediate Ruff/SwiftLint/detect-secrets blocking findings without lowering SAST gate policy.
    status: completed
  - id: revalidate-all
    content: Run lane-specific checks then full parallel run to verify 16/16 passes.
    status: completed
isProject: false
---

# Stabilize Parallel Test Lanes

## Goal
Return `25_run_all_tests_parallel.sh` to green by fixing the four failing lanes without weakening security policy, and with strict fuzz coverage as requested.

## Scope
- Fuzz lane: strict coverage path (increase effective per-test examples; keep strong gate)
- Classification persistence verification: protocol/readiness mismatch
- macOS UI regression lane: Xcode target source-list drift
- SAST lane: remediate blocking findings (Ruff/SwiftLint/detect-secrets)

## Planned Changes
- **Fuzz strictness alignment**
  - Update property tests under [tests/py/properties/test_classification_api_properties.py](tests/py/properties/test_classification_api_properties.py), [tests/py/properties/test_match_state_machine_properties.py](tests/py/properties/test_match_state_machine_properties.py), [tests/py/properties/test_teller_db_profile_properties.py](tests/py/properties/test_teller_db_profile_properties.py), and [tests/py/properties/test_teller_persist_properties.py](tests/py/properties/test_teller_persist_properties.py) so `@settings(max_examples=...)` is raised/removed to support high-example runs.
  - For finite input-space tests (notably match-state filter-count), widen strategies or make the gate logic in [14_run_fuzz_tests.sh](14_run_fuzz_tests.sh) treat finite-space exhaustion as compliant for per-test floor checks.
  - Keep strict gate behavior in [14_run_fuzz_tests.sh](14_run_fuzz_tests.sh) and reconcile docs/tests (ratio/defaults) in [README.md](README.md) and [requirements/13_run_fuzz_tests-requirements.md](requirements/13_run_fuzz_tests-requirements.md).

- **Classification persistence verifier transport fix**
  - In [21_classification_persistence_verification_test.sh](21_classification_persistence_verification_test.sh), ensure API startup and client URL use the same protocol (prefer explicit HTTP local mode when auto-starting the classifier, matching DAST behavior).
  - Harden readiness to require a successful `/health` response on the configured scheme instead of allowing port-open-only success.
  - Improve failure diagnostics by capturing classifier startup logs to an artifact file (instead of `/dev/null`) and printing pointer on curl failures.

- **macOS UI regression build fix**
  - Add [src/macos-ui/Sources/TransactionClassifier/LocalClassifierTLS.swift](src/macos-ui/Sources/TransactionClassifier/LocalClassifierTLS.swift) to the `TransactionClassifierUITestHost` target in [src/macos-ui/TransactionClassifierUIAutomation.xcodeproj/project.pbxproj](src/macos-ui/TransactionClassifierUIAutomation.xcodeproj/project.pbxproj).
  - Verify `APIClient.swift` references compile in both SwiftPM tests and Xcode UITest host build.

- **SAST blockers remediation (no policy downgrade)**
  - Resolve Ruff blocking findings in affected Python sources under [src/teller/](src/teller/) (primarily blank-line and trailing-whitespace issues).
  - Replace Swift force-unwrapping in [src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift](src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift) and [src/macos-ui/Tests/TransactionClassifierTests/LocalClassifierTLSTests.swift](src/macos-ui/Tests/TransactionClassifierTests/LocalClassifierTLSTests.swift).
  - Eliminate/ignore legacy `.ruff_cache` detect-secrets hit via cache-path cleanup and/or exclusion alignment in [06_run_static_security_tests.sh](06_run_static_security_tests.sh) and [.gitignore](.gitignore), while keeping scanner coverage intact.

## Verification Plan
- Run lane-level checks first:
  - `./14_run_fuzz_tests.sh`
  - `./21_classification_persistence_verification_test.sh`
  - `./16_run_macos_ui_regression_tests.sh`
  - `./06_run_static_security_tests.sh`
- Then run full parallel suite:
  - `./25_run_all_tests_parallel.sh`
- Confirm artifacts report no gate failures:
  - fuzz summary meets per-test/total targets
  - persistence verifier receives non-empty API response and DB row check passes
  - UITest host builds and executes smoke suite
  - `artifacts/security/reports/sast-summary.json` shows `gate_failed: false`