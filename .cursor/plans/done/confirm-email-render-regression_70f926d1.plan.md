---
name: confirm-email-render-regression
overview: Add requirement coverage and a focused macOS UI regression that fails when Confirm causes right-pane email rendering to be replaced by an error, then fix the reload/message-fetch path so the regression passes.
todos:
  - id: req-update
    content: Update macOS UI requirement for post-confirm right-pane email rendering continuity
    status: completed
  - id: ui-regression
    content: Add focused XCUITest step that asserts body remains and email-error does not appear after Confirm
    status: completed
  - id: prove-fail
    content: Run only that UI regression step and capture failing output
    status: completed
  - id: fix-bug
    content: Patch ViewModel/API confirm reload path so right-pane email rendering remains valid
    status: completed
  - id: prove-pass
    content: Rerun the same isolated UI regression step and confirm it passes
    status: completed
isProject: false
---

# Confirm Should Preserve Email Rendering

## Goal
Ensure pressing `Confirm` in Match & Classify does not replace the right-pane rendered email body with `email-error` when the selected candidate remains valid.

## Scope
- Requirements update for the expected post-confirm email-pane behavior.
- A targeted UI regression in the macOS XCUITest smoke suite, runnable as a single step.
- Bug fix in ViewModel/API interaction path used after confirm reload.

## Files to Change
- [requirements/macos-ui/MatchAndClassifyViews-requirements.md](requirements/macos-ui/MatchAndClassifyViews-requirements.md)
- [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift)
- [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift](src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift)
- [src/macos-ui/Sources/TransactionClassifier/APIClient.swift](src/macos-ui/Sources/TransactionClassifier/APIClient.swift) (if needed by fix)

## Implementation Plan
1. **Update requirements**
   - Add/extend a requirement in `MatchAndClassifyViews-requirements.md` stating: after a successful Confirm, if the transaction still has a selected candidate email, the right pane continues to display email body content and must not surface `email-error` for this flow.
   - Add traceable test intent that maps to the UI regression scenario.

2. **Add a failing UI regression scenario**
   - Extend the existing XCUITest smoke suite in `TransactionClassifierUITests.swift` with a dedicated step that:
     - opens a transaction with candidate/email body visible,
     - taps `Confirm`,
     - asserts email content remains present (`email-body-html`/email content affordance),
     - asserts `email-error` is absent.
   - Keep it isolated via `XCUITEST_STEPS` so it can run alone through `tests/t14_run_macos_ui_regression_tests.sh <step-number>`.

3. **Run regression step only and capture failure proof**
   - Run only the new step using the existing t14 single-step mechanism.
   - Record the assertion failure (missing body or visible `email-error`) as proof of reproduction.

4. **Fix confirm reload/email selection bug**
   - Adjust post-confirm reload path in `ClassificationViewModel+MatchReview.swift` so selected candidate/email state remains coherent across `loadAll()` and subsequent `fetchMessage` call.
   - Ensure stale-token or transient reload conditions do not clear right-pane body into `emailErrorText` for successful confirm flow.
   - If error mapping in `APIClient` contributes, harden that path minimally and keep requirement-aligned behavior.

5. **Re-run the same isolated regression step and verify pass**
   - Execute the exact same single-step command.
   - Confirm email body persists after Confirm and `email-error` is not shown.

6. **Sanity checks**
   - Run targeted related Swift test(s) if needed for confidence around confirm/reload behavior (without running full suite).

## Execution Commands (targeted)
- Repro/failing run (single UI step): `./tests/t14_run_macos_ui_regression_tests.sh <new-step-number>`
- Verify/passing run (same single UI step): `./tests/t14_run_macos_ui_regression_tests.sh <new-step-number>`
- Optional focused Swift test for touched logic: `swift test --package-path ./src/macos-ui --filter <specific-test-name>`