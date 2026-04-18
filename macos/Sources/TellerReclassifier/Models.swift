import Foundation

enum SaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

struct CategoryOption: Codable, Hashable, Identifiable {
    let nys_snw_category_id: Int
    let level_1: String?
    let level_1_name: String?
    let level_2: String?
    let level_2_name: String?
    let level_3: String?
    let level_4: String?
    let categorization: String?
    let applicability: String?
    let display_label: String
    var id: Int { nys_snw_category_id }
}

struct TransactionCategory: Codable, Hashable {
    let nys_snw_category_id: Int
    let display_label: String
}

struct TransactionRow: Codable, Identifiable, Hashable {
    let transaction_id: String
    let account_id: String
    let date: String
    let amount: Decimal
    let description: String
    let status: String
    let transaction_type_code: String?
    let teller_category: String?
    var classification: TransactionCategory?
    var id: String { transaction_id }
}

struct TransactionListResponse: Codable {
    let total: Int
    let items: [TransactionRow]
}

struct ClassificationMutation: Codable, Hashable {
    let transaction_id: String
    let nys_snw_category_id: Int?
}

struct ClassificationBatchRequest: Codable {
    let updates: [ClassificationMutation]
}

struct ClassificationWriteResponse: Codable, Hashable {
    let transaction_id: String
    let nys_snw_category_id: Int?
    let type: String
    let updated_at: String
}
