import Foundation

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
        return ConnectViewModel(api: UITestingFixtureConnectAPI())
    }
}

actor UITestingFixtureAPI: ClassificationAPI {
    private let pageSize: Int
    private let categories: [CategoryOption] = [
        .init(nys_snw_category_id: 101, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Dining", applicability: nil, display_label: "Dining"),
        .init(nys_snw_category_id: 102, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Utilities", applicability: nil, display_label: "Utilities"),
        .init(nys_snw_category_id: 103, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Transportation", applicability: nil, display_label: "Transportation"),
    ]
    private var rows: [TransactionRow] = [
        .init(transaction_id: "txn_001", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-20", amount: Decimal(string: "16.24")!, description: "Coffee Roasters", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_002", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-19", amount: Decimal(string: "88.50")!, description: "Electric Utility Co", status: "posted", transaction_type_code: "ach", teller_category: "utilities", classification: .init(nys_snw_category_id: 102, display_label: "Utilities")),
        .init(transaction_id: "txn_003", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-18", amount: Decimal(string: "44.10")!, description: "City Transit Card", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_004", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-17", amount: Decimal(string: "22.99")!, description: "Corner Market", status: "posted", transaction_type_code: "card_payment", teller_category: "groceries", classification: nil),
        .init(transaction_id: "txn_005", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-16", amount: Decimal(string: "65.00")!, description: "Lunch Club", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_006", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-15", amount: Decimal(string: "13.75")!, description: "Downtown Parking", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_007", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-14", amount: Decimal(string: "31.45")!, description: "Neighborhood Bakery", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_008", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-13", amount: Decimal(string: "55.20")!, description: "Gas Station Alpha", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_009", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-12", amount: Decimal(string: "9.99")!, description: "Streaming Service", status: "posted", transaction_type_code: "subscription", teller_category: "entertainment", classification: nil),
        .init(transaction_id: "txn_010", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-11", amount: Decimal(string: "124.60")!, description: "Grocery Warehouse", status: "posted", transaction_type_code: "card_payment", teller_category: "groceries", classification: nil),
        .init(transaction_id: "txn_011", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-10", amount: Decimal(string: "7.50")!, description: "Public Library Cafe", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_012", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-09", amount: Decimal(string: "245.00")!, description: "Rent Payment", status: "posted", transaction_type_code: "ach", teller_category: "housing", classification: nil),
        .init(transaction_id: "txn_013", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-08", amount: Decimal(string: "18.30")!, description: "Pharmacy Counter", status: "posted", transaction_type_code: "card_payment", teller_category: "health", classification: nil),
        .init(transaction_id: "txn_014", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-07", amount: Decimal(string: "42.00")!, description: "Hardware Shop", status: "posted", transaction_type_code: "card_payment", teller_category: "home", classification: nil),
        .init(transaction_id: "txn_015", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-06", amount: Decimal(string: "14.75")!, description: "Museum Cafe", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_016", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-05", amount: Decimal(string: "73.10")!, description: "Bookstore Downtown", status: "posted", transaction_type_code: "card_payment", teller_category: "entertainment", classification: nil),
        .init(transaction_id: "txn_017", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-04", amount: Decimal(string: "28.88")!, description: "Ride Share Trip", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_018", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-03", amount: Decimal(string: "92.40")!, description: "Airline Luggage Fee", status: "posted", transaction_type_code: "card_payment", teller_category: "travel", classification: nil),
    ]

    init(processInfo: ProcessInfo = .processInfo) {
        pageSize = Int(processInfo.environment["TELLER_UI_TEST_PAGE_SIZE"] ?? "2") ?? 2
    }

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
        let effectiveLimit = min(max(limit, 0), max(pageSize, 1))
        let upperBound = min(filtered.count, safeOffset + effectiveLimit)
        let page = Array(filtered[safeOffset..<upperBound])
        return TransactionListResponse(total: filtered.count, items: page)
    }

    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        for update in updates {
            guard let rowIndex = rows.firstIndex(where: { $0.transaction_id == update.transaction_id }) else {
                continue
            }
            let category = update.nys_snw_category_id.flatMap { categoryId in
                categories.first(where: { $0.nys_snw_category_id == categoryId }).map {
                    TransactionCategory(nys_snw_category_id: $0.nys_snw_category_id, display_label: $0.display_label)
                }
            }
            rows[rowIndex].classification = category
        }
        return updates.map {
            ClassificationWriteResponse(
                transaction_id: $0.transaction_id,
                nys_snw_category_id: $0.nys_snw_category_id,
                type: "user",
                updated_at: "2026-04-23T00:00:00Z"
            )
        }
    }
}

actor UITestingFixtureConnectAPI: ConnectAPI {
    private var contexts: [ConnectContext] = [
        ConnectContext(
            key: "default",
            source: "default",
            institution_id: "inst_alpha",
            enrollment_id: "enr_alpha",
            token_path: "/Users/test/.teller/auth_token.json",
            enrollment_path: "/Users/test/.teller/enrollment_id.txt"
        ),
        ConnectContext(
            key: "suffix:inst_beta",
            source: "suffix",
            institution_id: "inst_beta",
            enrollment_id: "enr_beta",
            token_path: "/Users/test/.teller/auth_token_inst_beta.json",
            enrollment_path: "/Users/test/.teller/enrollment_id_inst_beta.txt"
        ),
    ]

    func fetchStatus() async throws -> ConnectStatusResponse {
        ConnectStatusResponse(token_saved: true, saved_path: contexts.first?.token_path ?? "", error: "")
    }

    func fetchContexts() async throws -> [ConnectContext] {
        contexts
    }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        let institution = request.institutionIdHint.isEmpty ? "manual" : request.institutionIdHint
        switch request.action {
        case ConnectAction.reconnect.rawValue:
            if let index = contexts.firstIndex(where: { $0.key == request.targetKey }) {
                let row = contexts[index]
                contexts[index] = ConnectContext(
                    key: row.key,
                    source: row.source,
                    institution_id: row.institution_id,
                    enrollment_id: request.enrollmentId.isEmpty ? row.enrollment_id : request.enrollmentId,
                    token_path: row.token_path,
                    enrollment_path: row.enrollment_path
                )
            }
        case ConnectAction.add.rawValue:
            let key = "suffix:\(institution)"
            contexts.append(
                ConnectContext(
                    key: key,
                    source: "suffix",
                    institution_id: institution,
                    enrollment_id: request.enrollmentId,
                    token_path: "/Users/test/.teller/auth_token_\(institution).json",
                    enrollment_path: "/Users/test/.teller/enrollment_id_\(institution).txt"
                )
            )
        default:
            break
        }
        return ConnectStoreTokenResponse(ok: true, path: contexts.first?.token_path ?? "", enrollment_id_path: contexts.first?.enrollment_path ?? "")
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        contexts.removeAll { $0.key == targetKey }
        return ConnectDeleteContextResponse(ok: true, moved_token: nil, moved_enrollment: nil, remaining: contexts)
    }
}
