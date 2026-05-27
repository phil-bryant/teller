import Foundation
@testable import TransactionClassifier

/// Static fixtures for `SnapshotFixtureAPI`. Held in a sibling file with no
/// Swift function declarations so the multi-line `.init`/`Type(...)` calls
/// (which Lizard's heuristic Swift parser misreads as function declarations
/// with many parameters) do not pollute complexity metrics for
/// `ContentViewSnapshotTests.swift`.
enum SnapshotFixtureData {
    static let categories: [CategoryOption] = [
        diningCategory,
        utilitiesCategory,
        transportationCategory,
    ]

    static let rows: [TransactionRow] = [coffeeRow, utilitiesRow, transitRow]

    private static let diningCategory: CategoryOption =
        CategoryOption(nys_snw_category_id: 101, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Dining", applicability: nil, display_label: "Dining")

    private static let utilitiesCategory: CategoryOption =
        CategoryOption(nys_snw_category_id: 102, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Utilities", applicability: nil, display_label: "Utilities")

    private static let transportationCategory: CategoryOption =
        CategoryOption(nys_snw_category_id: 103, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Transportation", applicability: nil, display_label: "Transportation")

    private static let utilitiesClassification: TransactionCategory =
        TransactionCategory(nys_snw_category_id: 102, display_label: "Utilities")

    private static let transportationClassification: TransactionCategory =
        TransactionCategory(nys_snw_category_id: 103, display_label: "Transportation")

    private static let coffeeRow: TransactionRow =
        TransactionRow(transaction_id: "txn_001", account_id: "acc_1", institution_id: "inst_1", account_last_four: "1111", date: "2026-04-20", amount: snapshotAmount("16.24"), description: "Coffee Roasters", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil)

    private static let utilitiesRow: TransactionRow =
        TransactionRow(transaction_id: "txn_002", account_id: "acc_1", institution_id: "inst_1", account_last_four: "1111", date: "2026-04-19", amount: snapshotAmount("88.50"), description: "Electric Utility Co", status: "posted", transaction_type_code: "ach", teller_category: "utilities", classification: utilitiesClassification)

    private static let transitRow: TransactionRow =
        TransactionRow(transaction_id: "txn_003", account_id: "acc_1", institution_id: "inst_1", account_last_four: "1111", date: "2026-04-18", amount: snapshotAmount("44.10"), description: "City Transit Card", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: transportationClassification)

    private static func snapshotAmount(_ value: String) -> Decimal {
        Decimal(string: value) ?? .zero
    }
}
