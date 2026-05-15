import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import TransactionClassifier

final class ContentViewSnapshotTests: XCTestCase {
    private static let isRecording = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    private static let snapshotRecordMode: SnapshotTestingConfiguration.Record = isRecording ? .all : .never
    private static let volatileHexTokenPattern = #"\$[0-9a-f]{6,}"#
    private static let memoryAddressPattern = #"0x[0-9a-f]+"#
    private static let framePattern = #"f=\([^)]*\)"#
    private static let connectVolatileHierarchyMarkers = [
        "SwiftUI.KeyViewProxy",
        "SwiftUI._NSGraphicsView",
        "_FocusRingView",
    ]

    @MainActor
    func testEmptyStateSnapshot() async {
        // #R001
        await assertContentSnapshot(named: "empty-state") { viewModel in
            viewModel.transactions = []
            viewModel.totalTransactions = 0
            viewModel.selection = []
            viewModel.statusText = "Loaded 0 transactions"
        }
    }

    @MainActor
    func testLoadedSelectionSnapshot() async {
        await assertContentSnapshot(named: "loaded-selection") { viewModel in
            viewModel.selection = ["txn_001"]
            viewModel.selectionDidChange()
        }
    }

    @MainActor
    func testErrorBannerSnapshot() async {
        await assertContentSnapshot(named: "error-banner") { viewModel in
            viewModel.errorText = "Fixture load failed"
        }
    }

    @MainActor
    func testMixedSelectionSnapshot() async {
        await assertContentSnapshot(named: "mixed-selection") { viewModel in
            viewModel.selection = ["txn_001", "txn_002"]
            viewModel.selectionDidChange()
        }
    }

    @MainActor
    func testSaveStateIndicatorsSnapshot() async {
        await assertContentSnapshot(named: "save-state-indicators") { viewModel in
            viewModel.rowState["txn_001"] = .saving
            viewModel.rowState["txn_002"] = .saved(Date(timeIntervalSince1970: 1_713_651_200))
            viewModel.rowState["txn_003"] = .failed("Network timeout")
            viewModel.selection = ["txn_003"]
            viewModel.selectionDidChange()
        }
    }

    @MainActor
    func testConnectTabSnapshot() async {
        await assertConnectSnapshot(named: "connect-tab") { _ in }
    }

    @MainActor
    func testConnectTabErrorSnapshot() async {
        await assertConnectSnapshot(named: "connect-tab-error") { viewModel in
            viewModel.errorText = "Delete failed: context not found"
        }
    }

    @MainActor
    private func assertContentSnapshot(named: String, configure: (ClassificationViewModel) -> Void) async {
        let viewModel = ClassificationViewModel(api: SnapshotFixtureAPI())
        viewModel.onlyUnclassified = false
        await viewModel.loadAll()
        configure(viewModel)

        let view = NSHostingView(
            rootView: ContentView(
                viewModel: viewModel,
                connectViewModel: ConnectViewModel(
                    api: SnapshotFixtureConnectAPI(),
                    setupAPI: SnapshotFixtureSetupAPI()
                ),
                autoLoadOnAppear: false
            )
                .frame(width: 1120, height: 720)
        )
        view.frame = NSRect(x: 0, y: 0, width: 1120, height: 720)
        view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: normalizeRecursiveDescription(snapshotRecursiveDescription(view)),
            as: .lines,
            named: named,
            record: Self.snapshotRecordMode
        )
    }

    @MainActor
    private func assertConnectSnapshot(named: String, configure: (ConnectViewModel) -> Void) async {
        let classificationViewModel = ClassificationViewModel(api: SnapshotFixtureAPI())
        classificationViewModel.onlyUnclassified = false
        await classificationViewModel.loadAll()

        let connectViewModel = ConnectViewModel(
            api: SnapshotFixtureConnectAPI(),
            setupAPI: SnapshotFixtureSetupAPI()
        )
        await connectViewModel.loadAll()
        configure(connectViewModel)

        let view = NSHostingView(
            rootView: ContentView(
                viewModel: classificationViewModel,
                connectViewModel: connectViewModel,
                autoLoadOnAppear: false,
                startTab: "connect"
            )
            .frame(width: 1120, height: 720)
        )
        view.frame = NSRect(x: 0, y: 0, width: 1120, height: 720)
        view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: normalizeRecursiveDescription(
                snapshotRecursiveDescription(view),
                stripConnectVolatileInternals: true
            ),
            as: .lines,
            named: named,
            record: Self.snapshotRecordMode
        )
    }

    private func snapshotRecursiveDescription(_ view: NSView) -> String {
        let selector = NSSelectorFromString("recursiveDescription")
        guard view.responds(to: selector),
              let unmanaged = view.perform(selector) else {
            return String(describing: view)
        }
        return (unmanaged.takeUnretainedValue() as? String) ?? String(describing: view)
    }

    private func normalizeRecursiveDescription(
        _ snapshot: String,
        stripConnectVolatileInternals: Bool = false
    ) -> String {
        var normalized = snapshot.replacingOccurrences(
            of: Self.volatileHexTokenPattern,
            with: "$hash",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: Self.memoryAddressPattern,
            with: "0xaddr",
            options: .regularExpression
        )
        // AppKit computes control widths differently across macOS/SwiftUI versions.
        normalized = normalized.replacingOccurrences(
            of: Self.framePattern,
            with: "f=(...)",
            options: .regularExpression
        )
        guard stripConnectVolatileInternals else {
            return normalized
        }
        return stripVolatileHierarchyLines(from: normalized)
    }

    private func stripVolatileHierarchyLines(from snapshot: String) -> String {
        snapshot
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !Self.connectVolatileHierarchyMarkers.contains { marker in
                    line.contains(marker)
                }
            }
            .joined(separator: "\n")
    }
}

private func fixtureAmount(_ value: String) -> Decimal {
    Decimal(string: value) ?? .zero
}

actor SnapshotFixtureConnectAPI: ConnectAPI {
    func fetchStatus() async throws -> ConnectStatusResponse {
        ConnectStatusResponse(token_saved: false, saved_path: "", error: "")
    }

    func fetchContexts() async throws -> [ConnectContext] {
        [
            ConnectContext(
                key: "default",
                source: "default",
                institution_id: "inst_alpha",
                enrollment_id: "enr_alpha",
                token_path: "/tmp/auth_token.json",
                enrollment_path: "/tmp/enrollment_id.txt"
            ),
            ConnectContext(
                key: "suffix:inst_beta",
                source: "suffix",
                institution_id: "inst_beta",
                enrollment_id: "enr_beta",
                token_path: "/tmp/auth_token_inst_beta.json",
                enrollment_path: "/tmp/enrollment_id_inst_beta.txt"
            ),
        ]
    }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        _ = request
        return ConnectStoreTokenResponse(ok: true, path: "/tmp/auth_token.json", enrollment_id_path: "/tmp/enrollment_id.txt")
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        _ = targetKey
        return ConnectDeleteContextResponse(ok: true, moved_token: nil, moved_enrollment: nil, remaining: [])
    }

    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession {
        if action == .reconnect {
            guard let selectedContext else {
                throw ConnectServiceError.validation("Select a context before reconnecting.")
            }
            return ConnectStartSession(
                action: action,
                targetKey: selectedContext.key,
                applicationId: "app_snapshot",
                environment: "development",
                enrollmentId: selectedContext.enrollment_id
            )
        }
        return ConnectStartSession(
            action: action,
            targetKey: "",
            applicationId: "app_snapshot",
            environment: "development",
            enrollmentId: ""
        )
    }
}

actor SnapshotFixtureSetupAPI: TellerSetupAPI {
    private let snapshot = TellerSetupSnapshot(
        tellerDirectory: "/tmp/.teller",
        applicationIDPath: "/tmp/.teller/application_id.txt",
        certificatePath: "/tmp/.teller/certificate.pem",
        privateKeyPath: "/tmp/.teller/private_key.pem",
        authTokenPath: "/tmp/.teller/auth_token.json",
        hasApplicationID: true,
        hasCertificate: true,
        hasPrivateKey: true,
        hasAuthToken: true
    )

    func loadSnapshot() async throws -> TellerSetupSnapshot {
        snapshot
    }

    func saveApplicationID(_ applicationID: String) async throws -> String {
        _ = applicationID
        return snapshot.applicationIDPath
    }

    func saveAuthToken(_ token: String) async throws -> String {
        _ = token
        return snapshot.authTokenPath
    }

    func runSmokeCheck() async throws -> TellerSmokeCheckResult {
        TellerSmokeCheckResult(
            institutionsHTTPStatus: 200,
            institutionsCount: 12,
            accountsHTTPStatus: 200,
            warningText: ""
        )
    }
}

actor SnapshotFixtureAPI: ClassificationAPI {
    private let categories: [CategoryOption] = [
        .init(nys_snw_category_id: 101, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Dining", applicability: nil, display_label: "Dining"),
        .init(nys_snw_category_id: 102, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Utilities", applicability: nil, display_label: "Utilities"),
        .init(nys_snw_category_id: 103, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Transportation", applicability: nil, display_label: "Transportation"),
    ]

    private let rows: [TransactionRow] = [
        .init(transaction_id: "txn_001", account_id: "acc_1", institution_id: "inst_1", account_last_four: "1111", date: "2026-04-20", amount: fixtureAmount("16.24"), description: "Coffee Roasters", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_002", account_id: "acc_1", institution_id: "inst_1", account_last_four: "1111", date: "2026-04-19", amount: fixtureAmount("88.50"), description: "Electric Utility Co", status: "posted", transaction_type_code: "ach", teller_category: "utilities", classification: .init(nys_snw_category_id: 102, display_label: "Utilities")),
        .init(transaction_id: "txn_003", account_id: "acc_1", institution_id: "inst_1", account_last_four: "1111", date: "2026-04-18", amount: fixtureAmount("44.10"), description: "City Transit Card", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: .init(nys_snw_category_id: 103, display_label: "Transportation")),
    ]

    func fetchCategories() async throws -> [CategoryOption] {
        categories
    }

    func fetchTransactions(search: String, onlyUnclassified: Bool, limit: Int, offset: Int) async throws -> TransactionListResponse {
        let normalizedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = rows.filter { row in
            if onlyUnclassified && row.classification != nil {
                return false
            }
            guard !normalizedSearch.isEmpty else {
                return true
            }
            return row.description.lowercased().contains(normalizedSearch) || row.transaction_id.lowercased().contains(normalizedSearch)
        }
        let safeOffset = max(0, min(offset, filtered.count))
        let upperBound = min(filtered.count, safeOffset + max(limit, 0))
        return TransactionListResponse(total: filtered.count, items: Array(filtered[safeOffset..<upperBound]))
    }

    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        updates.map {
            ClassificationWriteResponse(
                transaction_id: $0.transaction_id,
                nys_snw_category_id: $0.nys_snw_category_id,
                type: "user",
                updated_at: "2026-04-23T00:00:00Z"
            )
        }
    }
}
