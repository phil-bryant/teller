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
    let institution_id: String?
    let account_last_four: String?
    let date: String
    let amount: Decimal
    let description: String
    let status: String
    let transaction_type_code: String?
    let teller_category: String?
    var classification: TransactionCategory?
    var id: String { transaction_id }

    enum CodingKeys: String, CodingKey {
        case transaction_id, account_id, institution_id, account_last_four, date, amount, description, status
        case transaction_type_code, teller_category, classification
    }

    init(transaction_id: String, account_id: String, institution_id: String? = nil, account_last_four: String? = nil,
         date: String, amount: Decimal, description: String, status: String, transaction_type_code: String?,
         teller_category: String?, classification: TransactionCategory?) {
        self.transaction_id = transaction_id
        self.account_id = account_id
        self.institution_id = institution_id
        self.account_last_four = account_last_four
        self.date = date
        self.amount = amount
        self.description = description
        self.status = status
        self.transaction_type_code = transaction_type_code
        self.teller_category = teller_category
        self.classification = classification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transaction_id = try c.decode(String.self, forKey: .transaction_id)
        account_id = try c.decode(String.self, forKey: .account_id)
        institution_id = try c.decodeIfPresent(String.self, forKey: .institution_id)
        account_last_four = try c.decodeIfPresent(String.self, forKey: .account_last_four)
        date = try c.decode(String.self, forKey: .date)
        description = try c.decode(String.self, forKey: .description)
        status = try c.decode(String.self, forKey: .status)
        transaction_type_code = try c.decodeIfPresent(String.self, forKey: .transaction_type_code)
        teller_category = try c.decodeIfPresent(String.self, forKey: .teller_category)
        classification = try c.decodeIfPresent(TransactionCategory.self, forKey: .classification)
        if let value = try? c.decode(Decimal.self, forKey: .amount) { amount = value; return }
        if let text = try? c.decode(String.self, forKey: .amount), let value = Decimal(string: text) { amount = value; return }
        throw DecodingError.dataCorruptedError(forKey: .amount, in: c, debugDescription: "amount must be decimal string/number")
    }
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
