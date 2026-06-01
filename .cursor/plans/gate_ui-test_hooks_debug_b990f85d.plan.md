---
name: Gate UI-test hooks DEBUG
overview: "Strip all UI-testing fixtures and launch-mode hooks from production (Release) builds by gating them behind #if DEBUG, while keeping Debug-built UI tests and swift test working."
todos:
  - id: gate-fixtures
    content: "Wrap the three UITestingFixture*API.swift file bodies in #if DEBUG/#endif (keeping imports and #Rxxx requirement-tag comments)."
    status: completed
  - id: gate-detection
    content: In UITestingSupport.swift, gate detectAppLaunchMode body so Release constant-folds to .normal (single-return form).
    status: completed
  - id: gate-builders
    content: "In UITestingSupport.swift, gate the .uiTesting fixture-instantiation branches of buildDefaultViewModel/buildDefaultConnectViewModel behind #if DEBUG."
    status: completed
  - id: verify-builds
    content: Verify swift build -c release (clean), swift build -c debug, and swift test all succeed.
    status: completed
isProject: false
---

# Gate UI-Testing Hooks Out of Production Builds

## Problem
A reviewer flagged that `UITestingFixtureClassificationAPI.swift`, `UITestingFixtureConnectAPI.swift`, and `UITestingFixtureSetupAPI.swift` live in `Sources/TransactionClassifier/` (the production app target), not a test target, so test hooks ship in the production binary.

## Why not just move them to a test target
XCUITest launches the real app as a separate process, so fixture code must be compiled into the app binary — test-target code cannot be injected. Moving them is not viable.

## Approach: `#if DEBUG` gating
Both UI-test schemes ([TransactionClassifierUITestHost.xcscheme](src/macos-ui/TransactionClassifierUIAutomation.xcodeproj/xcshareddata/xcschemes/TransactionClassifierUITestHost.xcscheme) and the `-CI` variant) use `buildConfiguration = "Debug"` for `Test`/`Launch`, and `Release` only for `Archive`. `swift test` and `swift build -c debug` are also Debug. So Debug builds keep the hooks (tests pass) and Release strips them (no production hooks). The codebase already uses `#if DEBUG` in [CrashReporterService.swift](src/macos-ui/Sources/TransactionClassifier/CrashReporterService.swift).

Per the chosen scope, gate ALL UI-testing machinery (fixtures + launch detection + spinner swap), not just the fixtures.

## Changes

### 1. Wrap each fixture file body in `#if DEBUG`
- [UITestingFixtureClassificationAPI.swift](src/macos-ui/Sources/TransactionClassifier/UITestingFixtureClassificationAPI.swift)
- [UITestingFixtureConnectAPI.swift](src/macos-ui/Sources/TransactionClassifier/UITestingFixtureConnectAPI.swift)
- [UITestingFixtureSetupAPI.swift](src/macos-ui/Sources/TransactionClassifier/UITestingFixtureSetupAPI.swift)

Keep `import Foundation` and the `// #Rxxx:` requirement-tag comments inside the file (traceability in [t04](tests/sh/t04_run_requirements_traceability_tests.bats) reads those tags). Shape: `import Foundation` then `#if DEBUG` ... existing content (including the `#Rxxx` comment) ... `#endif`. In Release these files compile to nothing; their explicit membership in the SwiftPM target and the Xcode host target's Sources phase stays valid.

### 2. Make launch detection constant-fold to `.normal` in Release — [UITestingSupport.swift](src/macos-ui/Sources/TransactionClassifier/UITestingSupport.swift)
Keep `AppLaunchMode`, `detectAppLaunchMode`, `uiTestingActive`, and `BusyIndicator` defined in ALL builds (they are referenced across production views: `TransactionClassifierApp.swift`, `ContentView.swift`, `MatchAndClassifyViews.swift`, `CategoryManagerViews.swift`). Gate only the detection body so Release can never enter UI-testing mode:

```swift
func detectAppLaunchMode(processInfo: ProcessInfo = .processInfo) -> AppLaunchMode {
    var mode: AppLaunchMode = .normal
    #if DEBUG
    if processInfo.arguments.contains("--ui-testing") || processInfo.environment["TELLER_UI_TEST_MODE"] == "1" {
        mode = .uiTesting
    }
    #endif
    return mode
}
```

This single change cascades: in Release `uiTestingActive` becomes `false`, every `detectAppLaunchMode() == .uiTesting` check is dead, and `BusyIndicator` always renders the real `ProgressView` — so no call sites in the view files need editing.

### 3. Gate the fixture-instantiation branches in the builder functions — [UITestingSupport.swift](src/macos-ui/Sources/TransactionClassifier/UITestingSupport.swift)
`buildDefaultViewModel`/`buildDefaultConnectViewModel` are called from production `TransactionClassifierApp.init()`, so they must exist in Release but must not reference the (now Debug-only) fixture types:

```swift
@MainActor
func buildDefaultViewModel(processInfo: ProcessInfo = .processInfo) -> ClassificationViewModel {
    var viewModel = ClassificationViewModel()
    #if DEBUG
    if detectAppLaunchMode(processInfo: processInfo) == .uiTesting {
        viewModel = ClassificationViewModel(api: UITestingFixtureAPI())
    }
    #endif
    return viewModel
}
```

Same pattern for `buildDefaultConnectViewModel` (real `ConnectViewModel()` by default; Debug-only `.uiTesting` branch using `UITestingFixtureConnectAPI`/`UITestingFixtureSetupAPI`). Use single-return/structured control flow per repo rules.

## What stays the same
- No edits to view files or the Xcode/SwiftPM target membership.
- Unit tests in `TransactionClassifierTests` (e.g. [UITestingSupportTests.swift](src/macos-ui/Tests/TransactionClassifierTests/UITestingSupportTests.swift), [UITestingFixtureClassificationAPITests.swift](src/macos-ui/Tests/TransactionClassifierTests/UITestingFixtureClassificationAPITests.swift)) run under Debug `swift test`, so the fixtures remain available.
- Requirement docs/tags unchanged.

## Verification
- `swift build --package-path ./src/macos-ui -c release --product TransactionClassifier` compiles with zero references to the fixtures (production binary clean).
- `swift build --package-path ./src/macos-ui -c debug --product TransactionClassifier` and `swift test --package-path ./src/macos-ui` pass.
- UI automation lane (`xcodebuild` Debug host) still launches with fixtures active.