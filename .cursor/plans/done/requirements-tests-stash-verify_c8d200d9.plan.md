---
name: requirements-tests-stash-verify
overview: Update affected requirements and requirement tests for the new Match & Classify layout, then prove the tests fail without the code changes and pass again after restoring them.
todos:
  - id: update-reqs
    content: Revise Match & Classify requirements to match current UI ownership/order and removed override-id behavior
    status: completed
  - id: update-tests
    content: Adjust requirement tests to assert the new structure (and remove stale MatchActionsBar assumptions)
    status: completed
  - id: stash-code-only
    content: Stash only source/UI code edits (not requirements/tests or messages.txt), run targeted tests expecting failure, then unstash and rerun expecting pass
    status: completed
isProject: false
---

# Requirements/Test Sync + Stash Verification

## Scope To Update
- Requirements source of truth:
  - [requirements/macos-ui/MatchAndClassifyViews-requirements.md](requirements/macos-ui/MatchAndClassifyViews-requirements.md)
- Requirement tests to align with those requirements:
  - [src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift](src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift)
- Keep existing functional/UI test updates already made in place:
  - [src/macos-ui/Tests/TransactionClassifierTests/ClassificationViewModelTests.swift](src/macos-ui/Tests/TransactionClassifierTests/ClassificationViewModelTests.swift)
  - [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift)

## Requirement Updates
- Update Match & Classify requirements to match implemented behavior:
  - `Transaction Classification` is in pane 1 under the Next/Refresh/Load-more row.
  - `Search Email` is an expandable/collapsible disclosure above actions.
  - Match actions (`Confirm`, `Override`, `No-email`, `Clear`) are in pane 2 under Search Email.
  - `Note (optional)` is below the action row.
  - Email list renders below note.
  - Override email-message-id manual input is removed.
  - 2/3 pane responsive behavior exists (3-pane when shorter; 2-pane with stacked right side when taller).

## Requirement Test Updates
- Replace stale assumptions in `MatchAndClassifyViewsRequirementsTests`:
  - Remove tests that require `private struct MatchActionsBar`.
  - Assert action buttons and ordering within `CandidatesPane` instead.
  - Assert note field placement after action controls and email list section placement below note.
  - Assert Search Email disclosure presence (`search-email-disclosure`) and section ordering.
  - Assert override-id field identifier is absent.
  - Add/adjust source-level checks for responsive split behavior (`GeometryReader`, height threshold, 2-pane `VSplitView` branch vs 3-pane branch).

## Stash/Run/Restore Procedure
- Use targeted test scope (as selected):
  - `swift test --package-path ./src/macos-ui --filter MatchAndClassifyViewsRequirementsTests`
- Stash only source-code edits (do **not** stash requirements/tests or `messages.txt`), using explicit path list:
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift](src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel+MatchReview.swift)
  - [src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift](src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift)
  - [src/macos-ui/Sources/TransactionClassifier/ContentView.swift](src/macos-ui/Sources/TransactionClassifier/ContentView.swift)
  - [src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift](src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift)
  - [src/macos-ui/Sources/TransactionClassifier/TransactionClassifierApp.swift](src/macos-ui/Sources/TransactionClassifier/TransactionClassifierApp.swift)
- Run targeted test command once while stashed; expect failures due requirements/tests ahead of code.
- Unstash those source files.
- Run the same targeted test command again; expect passing.

## Validation Output To Report
- The exact failing assertions from the stashed run.
- Confirmation that only intended files were stashed/restored.
- Passing result summary from the post-unstash rerun.
