import AppKit
import SwiftUI

@main
struct TransactionClassifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel: ClassificationViewModel
    @State private var connectViewModel: ConnectViewModel

    init() {
        CrashReporterService.start()
        _viewModel = State(initialValue: buildDefaultViewModel())
        _connectViewModel = State(initialValue: buildDefaultConnectViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, connectViewModel: connectViewModel)
                .frame(minWidth: 1120, minHeight: 720)
                .onAppear {
                    if detectAppLaunchMode() == .normal {
                        activateTransactionClassifierForInput()
                    }
                }
        }
        .commands {
            CommandGroup(after: .help) {
                // #R035: List all in-app keyboard shortcuts under Help for discoverability.
                Divider()
                Button("Keyboard Shortcuts") {}
                    .disabled(true)
                Button("Focus Search — Cmd+F") {}
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        activateTransactionClassifierForInput()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
