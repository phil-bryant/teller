import AppKit
import SwiftUI

@main
struct TransactionClassifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel: ClassificationViewModel
    @State private var connectViewModel: ConnectViewModel

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if detectAppLaunchMode() == .normal {
            CrashReporterService.start()
        }
        _viewModel = State(initialValue: buildDefaultViewModel())
        _connectViewModel = State(initialValue: buildDefaultConnectViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, connectViewModel: connectViewModel)
                // Keep enough vertical room so Match & Classify pane headers don't clip.
                .frame(minWidth: 800, minHeight: 375)
                .onAppear { activateTransactionClassifierForInput() }
        }
        .commands {
            CommandGroup(after: .help) {
                // #R035: List all in-app keyboard shortcuts under Help for discoverability.
                Divider()
                Button("Keyboard Shortcuts") {}
                    .disabled(true)
                Button("Next Unclassified — Cmd+]") {}
                    .disabled(true)
                Button("Undo — Cmd+Z") {}
                    .disabled(true)
                Button("Apply to Selected — Cmd+Return") {}
                    .disabled(true)
                Button("Save Category — Cmd+S") {}
                    .disabled(true)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = notification
        activateTransactionClassifierForInput()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        activateTransactionClassifierForInput()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        CrashReporterService.markGracefulShutdown()
    }
}
