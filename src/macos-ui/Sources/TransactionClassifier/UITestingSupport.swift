import Foundation
import SwiftUI

// #R001: Centralize app launch-mode detection for normal/runtime and UI-testing harness runs.
// #R005: Build default view models from launch mode so UI tests swap fixture-backed APIs.

enum AppLaunchMode {
    case normal
    case uiTesting
}

func detectAppLaunchMode(processInfo: ProcessInfo = .processInfo) -> AppLaunchMode {
    var mode: AppLaunchMode = .normal
    #if DEBUG
    if processInfo.arguments.contains("--ui-testing") || processInfo.environment["TELLER_UI_TEST_MODE"] == "1" {
        mode = .uiTesting
    }
    #endif
    return mode
}

/// Resolved once at process start. UI-test/automation runs set `TELLER_UI_TEST_MODE=1`.
let uiTestingActive: Bool = detectAppLaunchMode() == .uiTesting

/// Loading indicator that spins in normal runs but renders a static, non-animating glyph under
/// UI testing. An indeterminate `ProgressView` animates continuously, which keeps the app from
/// ever reaching the "idle" state XCUITest waits for before each interaction — so every step
/// stalls while any spinner is on screen. A static placeholder lets the harness settle instantly.
struct BusyIndicator: View {
    var body: some View {
        if uiTestingActive {
            Image(systemName: "arrow.clockwise")
                .controlSize(.small)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

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

@MainActor
func buildDefaultConnectViewModel(processInfo: ProcessInfo = .processInfo) -> ConnectViewModel {
    var viewModel = ConnectViewModel()
    #if DEBUG
    if detectAppLaunchMode(processInfo: processInfo) == .uiTesting {
        viewModel = ConnectViewModel(api: UITestingFixtureConnectAPI(), setupAPI: UITestingFixtureSetupAPI())
    }
    #endif
    return viewModel
}
