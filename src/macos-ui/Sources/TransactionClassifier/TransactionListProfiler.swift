import Foundation

/// Optional timing logs for transaction list load and first SwiftUI paint (stderr).
enum TransactionListProfiler {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TELLER_UI_PROFILE_TRANSACTION_LIST"] == "true"
    }

    private static let clock = ContinuousClock()
    private static var loadStart: ContinuousClock.Instant?
    private static var busyClearedAt: ContinuousClock.Instant?

    static func beginLoad() {
        guard isEnabled else { return }
        loadStart = clock.now
        busyClearedAt = nil
        log("load.start")
    }

    static func markCategoriesLoaded() {
        logSinceStart("load.categories_done")
    }

    static func markTransactionsFetched(itemCount: Int, milliseconds: Double) {
        log("load.transactions_fetch_ms=\(formatMs(milliseconds)) items=\(itemCount)")
    }

    static func markTransactionsAssigned(rowCount: Int) {
        logSinceStart("load.state_assigned rows=\(rowCount)")
    }

    static func markBusyCleared() {
        guard isEnabled, let loadStart else { return }
        let now = clock.now
        busyClearedAt = now
        let ms = milliseconds(from: loadStart, to: now)
        log("load.busy_cleared since_start_ms=\(formatMs(ms))")
    }

    static func markListRendered(rowCount: Int) {
        guard isEnabled, let loadStart else { return }
        let now = clock.now
        let sinceStart = milliseconds(from: loadStart, to: now)
        if let busyClearedAt {
            let sinceBusy = milliseconds(from: busyClearedAt, to: now)
            log(
                "list.rendered rows=\(rowCount) since_busy_cleared_ms=\(formatMs(sinceBusy)) "
                    + "since_start_ms=\(formatMs(sinceStart))"
            )
        } else {
            log("list.rendered rows=\(rowCount) since_start_ms=\(formatMs(sinceStart))")
        }
        Self.loadStart = nil
        Self.busyClearedAt = nil
    }

    static func markLoadFailed(_ message: String) {
        log("load.failed \(message)")
        loadStart = nil
        busyClearedAt = nil
    }

    private static func logSinceStart(_ label: String) {
        guard isEnabled, let loadStart else { return }
        let ms = milliseconds(from: loadStart, to: clock.now)
        log("\(label) since_start_ms=\(formatMs(ms))")
    }

    private static func log(_ message: String) {
        guard isEnabled else { return }
        fputs("[teller-ui-profile] \(message)\n", stderr)
    }

    static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let elapsed = end - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func formatMs(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
