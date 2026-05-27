# Transaction Classifier Category Manager View Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/CategoryManagerViews.swift`.

R040  Statement: Manage Categories supports multi-select and bulk delete.
Design: `CategoryManagerView` keeps category selection in a `Set<Int>`. Plain click selects one row; Command-click toggles rows in the set. The sidebar header exposes a Delete action enabled when one or more categories are selected. When exactly one category is selected the edit form is active; when multiple are selected the form is disabled and the header shows the selection count.
Tests:
- R040-T01: Command-click two categories and verify Delete is enabled; trigger bulk delete and verify both categories are removed from the list.
- R040-T02: In the Manage Categories smoke edit scenario, clear/replace only the populated Categorization field before saving (`Dining` -> `Dining Updated`) and keep other draft fields paste-only to avoid unnecessary UI latency.

## Changelog

- 2026-05-26: Extracted category-management requirements from `ContentView-requirements.md` after view-file split.
