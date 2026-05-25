---
name: README freshness audit
overview: Document drift exists between README and current code/workflows, especially around script 18, test commands, and setup prerequisites. This plan captures high-impact fixes to bring docs back in sync with current architecture.
todos:
  - id: fix-script18-docs
    content: Update README and related references to remove non-existent script 18 mentions and document current script 18 behavior.
    status: completed
  - id: add-setup-prereqs
    content: Add missing DB profile and Postgres prerequisite steps to Quick Start and setup sections.
    status: completed
  - id: correct-test-docs
    content: Align test documentation with tests/py path and multi-lane behavior in 09_run_shell_unit_tests.sh.
    status: completed
  - id: refresh-connect-docs
    content: Update Connect/classifier setup docs to reflect in-process Connect and current token/env requirements.
    status: completed
  - id: improve-repo-map
    content: Add concise repository structure and architecture context for contributors.
    status: completed
isProject: false
---

# README Freshness And Coverage Plan

## Goal
Bring repository documentation in sync with current implementation, with priority on onboarding-breaking inaccuracies and missing setup/test details.

## Findings To Address First
- `README.md` references non-existent `18_configure_teller_io.sh`; actual script is [`18_run_all_checks_parallel.sh`](/Users/phil/local/src/teller/18_run_all_checks_parallel.sh).
- Quick Start in [`README.md`](/Users/phil/local/src/teller/README.md) omits required DB profile setup (`db-profiles.json`) before running DB scripts.
- Unit test commands in [`README.md`](/Users/phil/local/src/teller/README.md) point to wrong paths; tests live under [`tests/py/`](/Users/phil/local/src/teller/tests/py) and script orchestration is in [`09_run_shell_unit_tests.sh`](/Users/phil/local/src/teller/09_run_shell_unit_tests.sh).
- Connect/Teller provisioning docs are stale: macOS Connect flow is in-process via [`ConnectAPIClient.swift`](/Users/phil/local/src/teller/macos-ui/Sources/TransactionClassifier/ConnectAPIClient.swift) and setup logic in [`TellerSetupService.swift`](/Users/phil/local/src/teller/macos-ui/Sources/TransactionClassifier/TellerSetupService.swift), not a separate token server script.
- Root docs understate current system scope (Python ingest + FastAPI classifier + SwiftUI app + SQL schema + multi-lane checks).

## Proposed Documentation Updates
1. **Fix broken script references in root README**
   - Replace all `18_configure_teller_io.sh` mentions with the current flow and/or `18_run_all_checks_parallel.sh` in [`README.md`](/Users/phil/local/src/teller/README.md).
   - Update stale auxiliary reference in [`.gitleaksignore`](/Users/phil/local/src/teller/.gitleaksignore).

2. **Repair Quick Start prerequisites**
   - Add explicit DB profile bootstrap step using [`db-profiles-EXAMPLE.json`](/Users/phil/local/src/teller/db-profiles-EXAMPLE.json).
   - Clarify when local Postgres must already be installed/running before [`07_deploy_database.sh`](/Users/phil/local/src/teller/07_deploy_database.sh).

3. **Correct and expand test documentation**
   - Update direct Python unittest command to `tests/py`.
   - Describe `09_run_shell_unit_tests.sh` multi-lane behavior (Python, shell bats, SQL pgTAP, Swift).
   - Link shell-test conventions from [`tests/sh/README.md`](/Users/phil/local/src/teller/tests/sh/README.md).

4. **Refresh Connect and classifier API setup docs**
   - Align root and macOS docs with in-process Connect architecture and launcher behavior in [`17_run_classification_macos-ui.sh`](/Users/phil/local/src/teller/17_run_classification_macos-ui.sh).
   - Clarify required classifier write token setup used by [`14_run_classification_api.py`](/Users/phil/local/src/teller/14_run_classification_api.py) and mutation paths.

5. **Improve repository orientation section**
   - Add a concise layout map covering [`teller/`](/Users/phil/local/src/teller/teller), [`macos-ui/`](/Users/phil/local/src/teller/macos-ui), [`sql/postgres/`](/Users/phil/local/src/teller/sql/postgres), [`tests/`](/Users/phil/local/src/teller/tests), and [`requirements/`](/Users/phil/local/src/teller/requirements).
   - Separate “implemented in this repo” vs “external ecosystem components” in architecture notes.

## Validation Checklist
- Every script referenced in docs exists and matches behavior.
- Setup sequence works for a fresh clone without hidden assumptions.
- Test commands in docs match actual paths and orchestrator defaults.
- Connect/classifier docs match current code paths and env vars.
- No stale references to removed scripts or legacy token-server flow remain.
