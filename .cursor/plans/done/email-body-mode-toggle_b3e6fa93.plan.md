---
name: email-body-mode-toggle
overview: "Add a Mailcart-style email body mode toggle to Teller’s Match & Classify pane with the selected semantics: default to Rendered on each email selection, and in Raw mode prefer plain text over HTML source."
todos:
  - id: add-email-body-mode-state
    content: Add Email body display mode enum/state and reset-on-email-selection behavior in MatchAndClassifyViews.swift
    status: completed
  - id: add-email-mode-toggle-ui
    content: Add Rendered/Raw segmented toggle with accessibility identifiers in EmailSection header
    status: completed
  - id: implement-raw-rendered-branch
    content: Branch EmailBodyContent rendering by mode; keep rendered behavior and implement raw text-first fallback to html source
    status: completed
  - id: update-fixtures-and-ui-tests
    content: Add dual-body fixture data and extend UITests to validate default, toggle, and reset semantics
    status: completed
  - id: update-requirements-and-trace-tests
    content: Update requirements doc and MatchAndClassifyViewsRequirementsTests for new toggle semantics
    status: completed
isProject: false
---

# Add Raw vs Rendered Email Body Mode in Teller

## Goal
Implement a mode switch in Teller’s email pane so users can view email content as either rendered HTML or raw source/text, with behavior matching your selections:
- Default to `Rendered` whenever a different email is selected.
- In `Raw` mode, show plain text first, then fall back to raw HTML source.

## Implementation Plan

1. Add explicit body display mode state and reset behavior in the email pane UI.
   - Update [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift) to introduce a local enum/state (e.g., `EmailBodyDisplayMode`) in `EmailSection`.
   - Reset that state to `Rendered` when `selectedEmail?.id` changes, so each newly selected message starts rendered.

2. Add a header toggle control for mode selection.
   - In `EmailSection` (same file), add a segmented `Picker` (Rendered/Raw) near the existing "Email" header/spinner controls.
   - Add stable accessibility identifiers for both segments and the control container so UI tests can interact deterministically.

3. Split rendered vs raw rendering paths with your selected raw semantics.
   - In `EmailBodyContent` (same file), branch on display mode:
     - `Rendered`: keep existing behavior (`html_body` via `EmailBodyWebView`, text fallback, empty fallback).
     - `Raw`: render monospaced/selectable source where `text_body` is preferred, and `html_body` source is used only when text is absent.
   - Ensure raw HTML is presented as literal source (not interpreted), preserving line breaks and making it copy-friendly.

4. Keep HTML wrapping/scroll support unchanged for rendered mode.
   - Preserve existing helpers in [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/EmailAmountScrollSupport.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/EmailAmountScrollSupport.swift) for rendered mode only.
   - Ensure raw mode does not rely on WKWebView-specific behaviors or amount-scroll injection.

5. Update fixtures and UI tests to cover both modes.
   - Extend fixture coverage in [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/UITestingFixtureClassificationAPI.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/UITestingFixtureClassificationAPI.swift) with at least one message containing both `text_body` and `html_body`.
   - Update UI tests in [`/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift`](/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift) to:
     - verify default is Rendered after selecting an email,
     - switch to Raw and assert text-first output,
     - optionally verify reset to Rendered when selecting another email.

6. Update requirement traceability/tests for the new behavior.
   - Add/extend requirement text in [`/Users/phil/local/src/teller/requirements/macos-ui/MatchAndClassifyViews-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/MatchAndClassifyViews-requirements.md) describing the mode toggle and raw text-first rule.
   - Update source-anchored requirement checks in [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift) for new identifiers/requirement markers.

## Validation
- Run macOS UI tests focused on email pane behavior and new toggle interactions.
- Run requirement/source consistency tests.
- Manually verify in app: select email -> Rendered by default, toggle Raw -> text shown when present, switch to another email -> Rendered again.
