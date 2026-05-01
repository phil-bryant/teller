import AppKit
import SwiftUI

@main
struct TransactionClassifierApp: App {
    @State private var viewModel: ClassificationViewModel
    @State private var connectViewModel: ConnectViewModel

    init() {
        _viewModel = State(initialValue: buildDefaultViewModel())
        _connectViewModel = State(initialValue: buildDefaultConnectViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, connectViewModel: connectViewModel)
                .frame(minWidth: 1120, minHeight: 720)
                .onAppear {
                    if detectAppLaunchMode() == .normal {
                        bringAppToFront()
                    }
                }
        }
    }
}

@MainActor
private func bringAppToFront() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
