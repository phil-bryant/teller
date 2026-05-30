---
name: requirements-tests-1-10-alignment
overview: Align requirements and test coverage with implemented remediations for findings 1-10, ensuring traceability (R IDs, source tags, and test tags) passes for shell/security and macOS paths.
todos:
  - id: align-reqs-shell-1-5
    content: Update shell/security requirements docs and add IDs for findings 1-5
    status: completed
  - id: align-tests-shell-1-5
    content: Update/add shell bats tests for findings 1-5 requirement IDs
    status: completed
  - id: align-reqs-macos-6-10
    content: Update macOS requirements docs and IDs for findings 6-10
    status: completed
  - id: align-tests-macos-6-10
    content: Update/add Swift tests for findings 6-10 requirement coverage
    status: completed
  - id: run-traceability-and-regressions
    content: Run t04 plus targeted shell/swift/security suites and close any remaining R/T mapping gaps
    status: completed
isProject: false
---

# Plan: Update Requirements and Tests for Findings 1-10

## Goal
Bring requirements docs and tests into sync with the implemented remediations so behavior, documentation, and traceability gates are consistent.

## Workstream A: Findings 1-5 (Shell/Security)
- Update requirements for DB/script hardening and restore integrity:
  - [`/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md`](/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/98_destroy_database-requirements.md`](/Users/phil/local/src/teller/requirements/98_destroy_database-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/99_restore_database-requirements.md`](/Users/phil/local/src/teller/requirements/99_restore_database-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/97_backup_database-requirements.md`](/Users/phil/local/src/teller/requirements/97_backup_database-requirements.md)
- Add/adjust requirement IDs for:
  - identifier validation + parameterized SQL for DB/schema/table inputs (#1-#3)
  - static/dynamic Schemathesis token redaction artifacts (#4)
  - manifest generation/verification + tightened backup permissions (#5)
- Update shell tests accordingly:
  - [`/Users/phil/local/src/teller/tests/sh/05_deploy_database.bats`](/Users/phil/local/src/teller/tests/sh/05_deploy_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats`](/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/99_restore_database.bats`](/Users/phil/local/src/teller/tests/sh/99_restore_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/97_backup_database.bats`](/Users/phil/local/src/teller/tests/sh/97_backup_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/t03_run_static_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/t03_run_static_security_tests.bats)
  - [`/Users/phil/local/src/teller/tests/sh/t12_run_dynamic_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/t12_run_dynamic_security_tests.bats)

## Workstream B: Findings 6-10 (macOS)
- Update macOS requirements docs for bridge trust, token handling, host policy, 1psa pinning, and email rendering safety:
  - [`/Users/phil/local/src/teller/requirements/macos-ui/ConnectView-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/ConnectView-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/macos-ui/ConnectAPIClient-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/ConnectAPIClient-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/macos-ui/APIClient-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/APIClient-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/macos-ui/MatchAndClassifyViews-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/MatchAndClassifyViews-requirements.md)
- Add/adjust tests for the new requirement IDs:
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectViewModelTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectViewModelTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectWebFlowHTMLTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectWebFlowHTMLTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectAPIClientTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectAPIClientTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/EmailAmountScrollSupportTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/EmailAmountScrollSupportTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift)

## Workstream C: Traceability and Verification
- Ensure scoped source tags exist for each new/updated requirement ID in relevant implementation files (shell + Swift).
- Ensure corresponding test tags (`R###-T##`) exist and map cleanly.
- Validate with:
  - [`/Users/phil/local/src/teller/tests/t04_run_requirements_traceability_tests.sh`](/Users/phil/local/src/teller/tests/t04_run_requirements_traceability_tests.sh)
  - [`/Users/phil/local/src/teller/tests/t07_run_shell_unit_tests.sh`](/Users/phil/local/src/teller/tests/t07_run_shell_unit_tests.sh)
  - [`/Users/phil/local/src/teller/tests/t10_run_swift_unit_tests.sh`](/Users/phil/local/src/teller/tests/t10_run_swift_unit_tests.sh)
  - security lanes as needed for redaction checks (`t03`, `t12`)

## Delivery Order
- Apply Workstream A first (findings 1-5) because those docs/tests are mostly script-local and unblock shell traceability quickly.
- Apply Workstream B second (findings 6-10) to align macOS requirements and unit-level requirements tests.
- Run Workstream C last to catch any missing R/T links and finalize a clean traceability state.
