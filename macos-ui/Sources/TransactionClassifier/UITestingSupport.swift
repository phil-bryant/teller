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
