import Foundation

// #R001: Centralize app launch-mode detection for normal/runtime and UI-testing harness runs.
// #R005: Build default view models from launch mode so UI tests swap fixture-backed APIs.

enum AppLaunchMode {
    case normal
    case uiTesting
}

func detectAppLaunchMode(processInfo: ProcessInfo = .processInfo) -> AppLaunchMode {
    if processInfo.arguments.contains("--ui-testing") || processInfo.environment["TELLER_UI_TEST_MODE"] == "1" {
        return .uiTesting
    }
    return .normal
}

@MainActor
func buildDefaultViewModel(processInfo: ProcessInfo = .processInfo) -> ClassificationViewModel {
    switch detectAppLaunchMode(processInfo: processInfo) {
    case .normal:
        return ClassificationViewModel()
    case .uiTesting:
        return ClassificationViewModel(api: UITestingFixtureAPI())
    }
}

@MainActor
func buildDefaultConnectViewModel(processInfo: ProcessInfo = .processInfo) -> ConnectViewModel {
    switch detectAppLaunchMode(processInfo: processInfo) {
    case .normal:
        return ConnectViewModel()
    case .uiTesting:
        return ConnectViewModel(api: UITestingFixtureConnectAPI(), setupAPI: UITestingFixtureSetupAPI())
    }
}
