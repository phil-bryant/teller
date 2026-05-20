import AppKit

@MainActor
func activateTransactionClassifierForInput() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
        window.makeKeyAndOrderFront(nil)
    }
}
