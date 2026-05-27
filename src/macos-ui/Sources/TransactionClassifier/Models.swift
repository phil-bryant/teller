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

struct CategoryMutationRequest: Codable, Hashable {
    let level_1: String?
    let level_1_name: String?
    let level_2: String?
    let level_2_name: String?
    let level_3: String?
    let level_4: String?
    let categorization: String?
    let applicability: String?
}

struct CategoryDeleteResponse: Codable, Hashable {
    let nys_snw_category_id: Int
    let deleted: Bool
}

struct TransactionCategory: Codable, Hashable {
    let nys_snw_category_id: Int
    let display_label: String
}

struct TransactionMatchInfo: Codable, Hashable {
    let match_id: Int
    let email_message_id: String?
    let state: String
    let ai_confidence: Double?
    let selected_by: String
    let moved_to_matchy_at: String?
    let match_count: Int
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
    var match: TransactionMatchInfo?
    var id: String { transaction_id }

    enum CodingKeys: String, CodingKey {
        case transaction_id, account_id, institution_id, account_last_four, date, amount, description, status
        case transaction_type_code, teller_category, classification, match
    }
}

extension TransactionRow {
    /// Custom decoding lives in an extension so the struct keeps Swift's synthesized
    /// memberwise initializer for tests/fixtures while satisfying Lizard's parameter
    /// threshold (direct property assignment avoids the 12-arg `self.init` call).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.transaction_id = try c.decode(String.self, forKey: .transaction_id)
        self.account_id = try c.decode(String.self, forKey: .account_id)
        self.institution_id = try c.decodeIfPresent(String.self, forKey: .institution_id)
        self.account_last_four = try c.decodeIfPresent(String.self, forKey: .account_last_four)
        self.date = try c.decode(String.self, forKey: .date)
        self.description = try c.decode(String.self, forKey: .description)
        self.status = try c.decode(String.self, forKey: .status)
        self.transaction_type_code = try c.decodeIfPresent(String.self, forKey: .transaction_type_code)
        self.teller_category = try c.decodeIfPresent(String.self, forKey: .teller_category)
        self.classification = try c.decodeIfPresent(TransactionCategory.self, forKey: .classification)
        self.match = try c.decodeIfPresent(TransactionMatchInfo.self, forKey: .match)
        self.amount = try TransactionRow.decodeAmount(from: c)
    }

    private static func decodeAmount(from container: KeyedDecodingContainer<CodingKeys>) throws -> Decimal {
        if let value = try? container.decode(Decimal.self, forKey: .amount) { return value }
        if let text = try? container.decode(String.self, forKey: .amount), let value = Decimal(string: text) { return value }
        throw DecodingError.dataCorruptedError(
            forKey: .amount,
            in: container,
            debugDescription: "amount must be decimal string/number"
        )
    }
}

struct TransactionListResponse: Codable {
    let total: Int
    let items: [TransactionRow]
}

/// Query parameters for `ClassificationAPI.fetchTransactions`.
///
/// Bundled into a single struct so the API surface stays readable and call sites
/// (UI loaders, fixtures, tests) can name only the fields they care about. Defaults
/// match the most common UI list-load query.
struct TransactionFetchOptions: Sendable, Equatable {
    var search: String = ""
    var onlyUnclassified: Bool = false
    var matchState: String = ""
    var onlyUnmovedMatch: Bool = false
    var startDate: String = ""
    var endDate: String = ""
    var institutionId: String = ""
    var minAmount: String = ""
    var maxAmount: String = ""
    var limit: Int = 150
    var offset: Int = 0
    var includeTotal: Bool = true
    var countOnly: Bool = false
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

struct MatchOverrideRequest: Codable, Hashable {
    let email_message_id: String
    let note: String?
}

struct MatchReviewActionResponse: Codable, Hashable {
    let match_id: Int
    let transaction_id: String
    let state: String
    let selected_by: String
    let updated_at: String
}

// JSON-tolerant container for reason_json blobs returned by the matchy candidate endpoint.
enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var prettyDescription: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(value)
        case .string(let value): return value
        case .array(let value): return "[" + value.map(\.prettyDescription).joined(separator: ", ") + "]"
        case .object(let value):
            return "{" + value.map { "\($0.key): \($0.value.prettyDescription)" }.sorted().joined(separator: ", ") + "}"
        }
    }
}

struct MatchCandidateRow: Codable, Hashable, Identifiable {
    let email_message_id: String
    let score: Double
    let reason_json: JSONValue?
    let email_received_at: String?
    let is_selected_by_ai: Bool
    let is_unmatched_email_priority: Bool
    let subject: String?
    let from: String?
    let snippet: String?
    let mailcart_error: String?

    var id: String { email_message_id }
}

struct EmailMessage: Codable, Hashable {
    let email_message_id: String
    let subject: String?
    let from: String?
    let to: String?
    let received_at: String?
    let html_body: String?
    let text_body: String?
    let snippet: String?
}

struct EmailSearchHit: Codable, Hashable, Identifiable {
    let email_message_id: String
    let subject: String?
    let from: String?
    let received_at: String?
    let snippet: String?

    var id: String { email_message_id }
}

/// Structured Mailcart search criteria for the Match & Classify candidates pane.
struct EmailSearchCriteria: Sendable, Equatable {
    var subject: String = ""
    var sender: String = ""
    var body: String = ""
    var receivedStartDate: String = ""
    var receivedEndDate: String = ""

    var hasActiveFilter: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !receivedStartDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !receivedEndDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func normalized() -> EmailSearchCriteria {
        EmailSearchCriteria(
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            sender: sender.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            receivedStartDate: receivedStartDate.trimmingCharacters(in: .whitespacesAndNewlines),
            receivedEndDate: receivedEndDate.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Summary string returned by the classifier search API and echoed in UI status.
    var querySummary: String {
        let parts = [
            subject.isEmpty ? nil : "subject:\(subject)",
            sender.isEmpty ? nil : "sender:\(sender)",
            body.isEmpty ? nil : "body:\(body)",
            receivedStartDate.isEmpty ? nil : "from:\(receivedStartDate)",
            receivedEndDate.isEmpty ? nil : "to:\(receivedEndDate)",
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }
}

struct EmailSearchResponse: Codable, Hashable {
    let query: String
    let items: [EmailSearchHit]
}
