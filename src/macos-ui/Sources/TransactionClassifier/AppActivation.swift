import AppKit

@objc(ApplicationMain)
final class ApplicationMain: NSApplication {
    override init() {
        super.init()
        setActivationPolicy(.regular)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setActivationPolicy(.regular)
    }

    override func finishLaunching() {
        setActivationPolicy(.regular)
        super.finishLaunching()
        activate(ignoringOtherApps: true)
        if let window = windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
func activateTransactionClassifierForInput() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
        window.makeKeyAndOrderFront(nil)
    }
}
