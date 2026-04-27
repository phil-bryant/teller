---
name: macos-ui-ui-regression
overview: Introduce deterministic automated UI regression testing for `macos-ui` by combining fast snapshot checks with targeted end-to-end UI flows, then wiring both into existing script-based verification.
todos:
  - id: snapshot-infra
    content: Add snapshot testing dependency/target in macos-ui and create deterministic view fixtures.
    status: completed
  - id: view-stability-hooks
    content: Add accessibility identifiers and test hooks in SwiftUI views for stable assertions.
    status: completed
  - id: xcuitest-smoke
    content: Create macOS XCUITest host and implement 3-5 critical user-flow smoke tests.
    status: completed
  - id: regression-script
    content: Add a dedicated macOS UI regression script and document usage in README files.
    status: completed
  - id: gates-rollout
    content: Define CI/local gating flags and rollout sequence for snapshot + XCUITest adoption.
    status: completed
isProject: false
---

# Automated UI Regression Plan for macos-ui

## Current Baseline
- The app is a Swift Package executable with a single test target and no UI/snapshot test infrastructure in [`./macos-ui/Package.swift`](./macos-ui/Package.swift).
- UI is concentrated in SwiftUI views under [`./macos-ui/Sources/TransactionClassifier/ContentView.swift`](./macos-ui/Sources/TransactionClassifier/ContentView.swift), backed by `ClassificationViewModel`.
- Existing verification is script-driven (`swift test`) via [`./04_run_unit_tests.sh`](./04_run_unit_tests.sh), with no UI automation lane.

## Recommendation (Two-layer Regression Strategy)
- Add **snapshot UI tests** for high-signal visual states (empty, loaded, selection, error banner, mixed selection) to catch layout/text regressions quickly.
- Add **XCUITest smoke flows** for keyboard-heavy critical paths (focus search, next unclassified, apply category, undo) to catch interaction regressions.
- Keep unit tests as-is for business logic; use snapshots + UI automation only for user-visible behavior.

## Phase 1: Deterministic Snapshot Tests in `macos-ui`
- Add a snapshot framework dependency to [`./macos-ui/Package.swift`](./macos-ui/Package.swift) (e.g., Point-Free `SnapshotTesting`) and create a dedicated snapshot test target.
- Introduce test fixtures/builders that construct `ContentView` with predictable in-memory state (no live API/network).
- Add accessibility identifiers in [`./macos-ui/Sources/TransactionClassifier/ContentView.swift`](./macos-ui/Sources/TransactionClassifier/ContentView.swift) for stable targeting and future UI tests.
- Add a record-vs-assert mode (env-guarded) so baselines are easy to update intentionally.

## Phase 2: Add XCUITest App-level Smoke Tests
- Create an Xcode-based UI test host project (or generate one under `macos-ui/`) that launches `TransactionClassifier` and runs macOS UI tests.
- Add launch arguments/environment for test mode (fixture dataset, disable animation/timing sensitivities, deterministic locale/timezone where needed).
- Implement 3-5 smoke scenarios:
  - Search/filter and list selection behavior.
  - `Cmd+]` next-unclassified navigation.
  - Apply category to selected rows and verify updated label/state.
  - Undo (`Cmd+Z`) reverts visible classification state.
- Use accessibility IDs instead of text-only queries for durability.

## Phase 3: Integrate Into Existing Verification Scripts
- Add a new script (e.g., `./15_run_macos_ui_regression_tests.sh`) with two stages:
  - Stage A: `swift test` snapshot lane.
  - Stage B: `xcodebuild test` UI smoke lane (only on macOS with Xcode).
- Wire script into repo verification docs at [`./macos-ui/README.md`](./macos-ui/README.md) and [`./README.md`](./README.md).
- Optionally call this script from [`./04_run_unit_tests.sh`](./04_run_unit_tests.sh) behind a flag (e.g., `RUN_MACOS_UI_REGRESSION_TESTS=true`) to keep local defaults fast.

## Suggested Test Matrix (Initial)
- Snapshot states:
  - Empty/no selection.
  - Loaded list with one selected row.
  - Error banner visible.
  - Mixed-category selection state.
  - Save state indicators (`idle/saving/saved/failed`).
- UI smoke flows:
  - Keyboard shortcuts in toolbar (`Cmd+F`, `Cmd+]`, `Cmd+Z`).
  - Category typeahead choose + apply path.
  - Load more interaction and status text update.

## Quality Gates
- PR gate 1: all existing unit tests pass.
- PR gate 2: snapshot diffs must be reviewed/approved when baselines change.
- PR gate 3: XCUITest smoke suite passes on macOS runner.

## Rollout Order
- Start with snapshots first (high ROI, low runtime cost), then add UI smoke tests for interaction-critical flows.
- Keep total UI suite under ~10 minutes to preserve developer feedback speed.
- Reassess flaky tests after first week; tighten selectors/fixtures before expanding coverage.