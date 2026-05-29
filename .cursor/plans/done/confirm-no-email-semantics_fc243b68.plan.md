---
name: confirm-no-email-semantics
overview: Restore correct Confirm behavior so selecting the top candidate from a no-email match results in a confirmed state (not overridden), with requirements-first and fail-first test proof.
todos:
  - id: req-gap-update
    content: Update macOS + API requirements to define confirm semantics for no-email candidate confirm
    status: completed
  - id: tests-add-first
    content: Add Swift and Python tests for new/updated requirement IDs before implementation
    status: completed
  - id: prove-fail-first
    content: Run new tests and capture expected failing evidence
    status: completed
  - id: implement-backend-confirm-path
    content: Implement backend confirm path that yields human_confirmed_ai_match with selected candidate
    status: completed
  - id: implement-macos-client-flow
    content: Update API client + ViewModel confirm flow to use the confirmed no-email path
    status: completed
  - id: prove-pass-after
    content: Rerun targeted + regression tests and confirm all pass
    status: completed
isProject: false
---

# Confirm No-Email Semantics (Requirements-First)

## 1) Analyze and patch requirement gaps first
- Update [requirements/macos-ui/ClassificationViewModel-requirements.md](/Users/phil/local/src/teller/requirements/macos-ui/ClassificationViewModel-requirements.md) to explicitly define: when current match is `ai_no_match_found` and user presses Confirm with a latest-run candidate, resulting state must be **confirmed** semantics (not override semantics).
- Add/adjust backend contract requirements in [requirements/teller/teller_classification_api-requirements.md](/Users/phil/local/src/teller/requirements/teller/teller_classification_api-requirements.md) to define confirm mutation support for no-email-with-selected-candidate flow.
- If request/response shape changes for confirm are needed, update [requirements/macos-ui/APIClient-requirements.md](/Users/phil/local/src/teller/requirements/macos-ui/APIClient-requirements.md) accordingly.

## 2) Add tests for updated requirements (before implementation)
- Swift ViewModel tests in [src/macos-ui/Tests/TransactionClassifierTests/ClassificationViewModelTests.swift](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ClassificationViewModelTests.swift):
  - Confirm on `ai_no_match_found` + selected latest-run candidate must produce confirmed status path, and must not call override path.
- API client tests in [src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift) if confirm endpoint payload/shape changes.
- Backend API tests in [tests/py/test_teller_classification_api.py](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py):
  - Existing no-email match + candidate email confirm transitions to `human_confirmed_ai_match` and sets `email_message_id`.
  - Reject invalid/non-candidate email for this confirm path.

## 3) Prove fail-first
- Run the newly added targeted tests only and capture expected failures before code changes.
- Keep failure output snippets showing assertion mismatch (state/path/endpoint behavior).

## 4) Implement requirements
- Backend-first implementation:
  - Update confirm endpoint in [src/teller/classification/app.py](/Users/phil/local/src/teller/src/teller/classification/app.py) to support no-email candidate confirm intent without forcing override state.
  - Reuse/extend transition logic in [src/teller/classification/services.py](/Users/phil/local/src/teller/src/teller/classification/services.py) to set `state=human_confirmed_ai_match` + `email_message_id` with candidate validation for this path.
  - Add/adjust schema in [src/teller/classification/schemas.py](/Users/phil/local/src/teller/src/teller/classification/schemas.py) if confirm accepts request body.
- macOS client updates:
  - Update confirm API usage in [src/macos-ui/Sources/TransactionClassifier/APIClient.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/APIClient.swift).
  - Update confirm action logic in [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift) to invoke confirmed path for no-email candidate confirm.
  - Keep derived enablement in [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift) aligned with latest-run candidate requirement.

## 5) Prove pass-after-fix
- Re-run the same targeted new tests and show they pass.
- Run regression checks:
  - `swift test --filter ClassificationViewModelTests`
  - `bash tests/t04_run_requirements_traceability_tests.sh`
- Report the before/after evidence succinctly (failed tests pre-fix, green post-fix).
