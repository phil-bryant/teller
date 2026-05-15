---
name: Stabilize Connect Snapshots
overview: Make the connect-tab macOS snapshot tests deterministic and resilient to SwiftUI/AppKit internal-view churn, without masking meaningful regressions.
todos:
  - id: audit-current-connect-snapshot-harness
    content: Inspect current connect snapshot harness and identify all nondeterministic setup dependencies.
    status: completed
  - id: add-deterministic-setup-fixture
    content: Inject a fixed Teller setup fixture into connect snapshot tests for stable setup state.
    status: completed
  - id: tighten-recursive-description-normalization
    content: Filter known volatile SwiftUI/AppKit internal wrapper nodes in normalization logic.
    status: completed
  - id: verify-and-refresh-baselines-if-needed
    content: Run macOS snapshot regression script and update only required connect baselines after stabilization.
    status: completed
isProject: false
---

# Stabilize Connect Snapshot Regressions

## Goal
Make `testConnectTabSnapshot` and `testConnectTabErrorSnapshot` stable across environments by removing non-deterministic setup state and filtering volatile SwiftUI/AppKit internals from string snapshots.

## Changes
- Update snapshot test setup in [macos-ui/Tests/TransactionClassifierSnapshotTests/ContentViewSnapshotTests.swift](macos-ui/Tests/TransactionClassifierSnapshotTests/ContentViewSnapshotTests.swift) to inject a deterministic `TellerSetupAPI` fixture into `ConnectViewModel` instead of relying on default real-disk `TellerSetupService`.
- Add a local snapshot fixture implementation in the same test target (or a nearby test helper file) that returns fixed setup status values for both normal and error connect snapshots.
- Strengthen `normalizeRecursiveDescription(_:)` in [macos-ui/Tests/TransactionClassifierSnapshotTests/ContentViewSnapshotTests.swift](macos-ui/Tests/TransactionClassifierSnapshotTests/ContentViewSnapshotTests.swift) to strip or canonicalize known volatile lines (`SwiftUI.KeyViewProxy`, selected focus-ring/internal graphics wrappers) while keeping semantic structure and user-visible control hierarchy checks intact.
- Re-run `./10_run_macos_ui_regression_tests.sh` and only re-record connect snapshot baselines if normalized deterministic output still differs for legitimate structure changes.

## Guardrails
- Keep production UI code unchanged in [macos-ui/Sources/TransactionClassifier/ConnectView.swift](macos-ui/Sources/TransactionClassifier/ConnectView.swift) and [macos-ui/Sources/TransactionClassifier/ConnectViewModel.swift](macos-ui/Sources/TransactionClassifier/ConnectViewModel.swift) unless tests reveal a true functional regression.
- Keep normalization narrowly targeted to private, toolchain-volatile wrappers so real regressions remain detectable.

## Validation
- Connect snapshot tests pass locally with no dependency on host `~/.teller` files.
- Existing non-connect snapshots still pass (no over-filtering side effects).
- Diffs for future failures should reflect meaningful view structure changes, not private SwiftUI plumbing noise.