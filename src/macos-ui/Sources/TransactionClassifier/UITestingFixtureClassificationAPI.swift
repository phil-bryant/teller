import Foundation

// #R010: Provide deterministic classification, match-review, and message fixtures for UI testing.

private func fixtureAmount(_ value: String) -> Decimal {
    Decimal(string: value) ?? .zero
}

actor UITestingFixtureAPI: ClassificationAPI {
    static let matchFixtureEmailId = "msg_receipt_001"
    static let matchFixtureTransactionId = "txn_001"
    static let matchFixtureMatchId = 501
    static let searchFixtureEmailId = "msg_search_001"

    private let pageSize: Int
    private let matchFixtureEnabled: Bool
    private var nextCategoryId = 200
    private var nextMatchId = 900
    private var categories: [CategoryOption] = UITestingFixtureAPI.seedCategories()
    private var rows: [TransactionRow] = UITestingFixtureAPI.seedTransactions()

    init(processInfo: ProcessInfo = .processInfo) {
        pageSize = Int(processInfo.environment["TELLER_UI_TEST_PAGE_SIZE"] ?? "2") ?? 2
        matchFixtureEnabled = processInfo.environment["TELLER_UI_TEST_MATCH_FIXTURE"] == "1"
        if matchFixtureEnabled {
            rows = UITestingFixtureAPI.applyFixtureMatches(to: rows)
        }
    }

    private static func applyFixtureMatches(to rows: [TransactionRow]) -> [TransactionRow] {
        let fixtureMatches = UITestingFixtureAPI.fixtureMatches()
        var updated = rows
        for index in updated.indices {
            let transactionId = updated[index].transaction_id
            if let match = fixtureMatches[transactionId] {
                updated[index].match = match
            }
        }
        return updated
    }

    private static func seedCategories() -> [CategoryOption] {
        let dining = CategoryOption(nys_snw_category_id: 101, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Dining", applicability: nil, display_label: "Dining")
        let utilities = CategoryOption(nys_snw_category_id: 102, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Utilities", applicability: nil, display_label: "Utilities")
        let transportation = CategoryOption(nys_snw_category_id: 103, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Transportation", applicability: nil, display_label: "Transportation")
        return [dining, utilities, transportation]
    }

    private static func seedTransactions() -> [TransactionRow] {
        let utilities = TransactionCategory(nys_snw_category_id: 102, display_label: "Utilities")
        let row1 = TransactionRow(transaction_id: "txn_001", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-20", amount: fixtureAmount("16.24"), description: "Coffee Roasters", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil)
        let row2 = TransactionRow(transaction_id: "txn_002", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-19", amount: fixtureAmount("88.50"), description: "Electric Utility Co", status: "posted", transaction_type_code: "ach", teller_category: "utilities", classification: utilities)
        let row3 = TransactionRow(transaction_id: "txn_003", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-18", amount: fixtureAmount("44.10"), description: "City Transit Card", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil)
        let row4 = TransactionRow(transaction_id: "txn_004", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-17", amount: fixtureAmount("22.99"), description: "Corner Market", status: "posted", transaction_type_code: "card_payment", teller_category: "groceries", classification: nil)
        let row5 = TransactionRow(transaction_id: "txn_005", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-16", amount: fixtureAmount("65.00"), description: "Lunch Club", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil)
        let row6 = TransactionRow(transaction_id: "txn_006", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-15", amount: fixtureAmount("13.75"), description: "Downtown Parking", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil)
        let row7 = TransactionRow(transaction_id: "txn_007", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-14", amount: fixtureAmount("31.45"), description: "Neighborhood Bakery", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil)
        let row8 = TransactionRow(transaction_id: "txn_008", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-13", amount: fixtureAmount("55.20"), description: "Gas Station Alpha", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil)
        let row9 = TransactionRow(transaction_id: "txn_009", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-12", amount: fixtureAmount("9.99"), description: "Streaming Service", status: "posted", transaction_type_code: "subscription", teller_category: "entertainment", classification: nil)
        let row10 = TransactionRow(transaction_id: "txn_010", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-11", amount: fixtureAmount("124.60"), description: "Grocery Warehouse", status: "posted", transaction_type_code: "card_payment", teller_category: "groceries", classification: nil)
        let row11 = TransactionRow(transaction_id: "txn_011", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-10", amount: fixtureAmount("7.50"), description: "Public Library Cafe", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil)
        let row12 = TransactionRow(transaction_id: "txn_012", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-09", amount: fixtureAmount("245.00"), description: "Rent Payment", status: "posted", transaction_type_code: "ach", teller_category: "housing", classification: nil)
        let row13 = TransactionRow(transaction_id: "txn_013", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-08", amount: fixtureAmount("18.30"), description: "Pharmacy Counter", status: "posted", transaction_type_code: "card_payment", teller_category: "health", classification: nil)
        let row14 = TransactionRow(transaction_id: "txn_014", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-07", amount: fixtureAmount("42.00"), description: "Hardware Shop", status: "posted", transaction_type_code: "card_payment", teller_category: "home", classification: nil)
        let row15 = TransactionRow(transaction_id: "txn_015", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-06", amount: fixtureAmount("14.75"), description: "Museum Cafe", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil)
        let row16 = TransactionRow(transaction_id: "txn_016", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-05", amount: fixtureAmount("73.10"), description: "Bookstore Downtown", status: "posted", transaction_type_code: "card_payment", teller_category: "entertainment", classification: nil)
        let row17 = TransactionRow(transaction_id: "txn_017", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-04", amount: fixtureAmount("28.88"), description: "Ride Share Trip", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil)
        let row18 = TransactionRow(transaction_id: "txn_018", account_id: "acc_002", institution_id: "inst_beta", account_last_four: "2222", date: "2026-04-03", amount: fixtureAmount("92.40"), description: "Airline Luggage Fee", status: "posted", transaction_type_code: "card_payment", teller_category: "travel", classification: nil)
        return [row1, row2, row3, row4, row5, row6, row7, row8, row9, row10, row11, row12, row13, row14, row15, row16, row17, row18]
    }

    private static func fixtureMatches() -> [String: TransactionMatchInfo] {
        let m1 = TransactionMatchInfo(match_id: matchFixtureMatchId, email_message_id: matchFixtureEmailId, state: "human_confirmed_ai_match", ai_confidence: 0.95, selected_by: "human", moved_to_matchy_at: nil, match_count: 1)
        let m4 = TransactionMatchInfo(match_id: 504, email_message_id: nil, state: "ai_no_match_found", ai_confidence: nil, selected_by: "human", moved_to_matchy_at: nil, match_count: 0)
        let m5 = TransactionMatchInfo(match_id: 505, email_message_id: "msg_uncertain_005", state: "ai_candidate_uncertain", ai_confidence: 0.54, selected_by: "ai", moved_to_matchy_at: nil, match_count: 1)
        let m6 = TransactionMatchInfo(match_id: 506, email_message_id: "msg_confident_006", state: "ai_match_confident", ai_confidence: 0.92, selected_by: "ai", moved_to_matchy_at: nil, match_count: 1)
        let m7 = TransactionMatchInfo(match_id: 507, email_message_id: "msg_overridden_007", state: "human_overrode_ai_match", ai_confidence: nil, selected_by: "human", moved_to_matchy_at: nil, match_count: 1)
        return ["txn_001": m1, "txn_004": m4, "txn_005": m5, "txn_006": m6, "txn_007": m7]
    }

    private static func wideReceiptTextBody(orderTotalLine: String) -> String {
        let padding = String(repeating: " ", count: 240)
        let filler = (0..<40).map { "Line \($0) \(padding)" }.joined(separator: "\n")
        return """
        Coffee Roasters receipt
        \(filler)
        Subtotal $12.00
        Sales Tax $4.24
        \(orderTotalLine)
        Thank you for your order
        """
    }

    private static func displayLabel(for category: CategoryMutationRequest, fallbackId: Int) -> String {
        let fields = [
            category.categorization,
            category.level_4,
            category.level_3,
            category.level_2_name,
            category.level_1_name,
        ]
        if let first = fields.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
            return first
        }
        return "Category \(fallbackId)"
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func nextFixtureMatchId() -> Int {
        defer { nextMatchId += 1 }
        return nextMatchId
    }

    private func updateMatch(
        on transactionId: String,
        state: String,
        selectedBy: String,
        emailMessageId: String?,
        preserveMatchId: Bool = true
    ) throws -> MatchReviewActionResponse {
        guard let index = rows.firstIndex(where: { $0.transaction_id == transactionId }) else {
            throw APIError.requestFailed("Transaction \(transactionId) not found in fixture.")
        }

        let matchId: Int
        if preserveMatchId, let existing = rows[index].match?.match_id {
            matchId = existing
        } else {
            matchId = nextFixtureMatchId()
        }

        rows[index].match = TransactionMatchInfo(
            match_id: matchId,
            email_message_id: emailMessageId,
            state: state,
            ai_confidence: nil,
            selected_by: selectedBy,
            moved_to_matchy_at: nil,
            match_count: emailMessageId == nil ? 0 : 1
        )

        return MatchReviewActionResponse(
            match_id: matchId,
            transaction_id: transactionId,
            state: state,
            selected_by: selectedBy,
            updated_at: Self.isoNow()
        )
    }

    func fetchCategories() async throws -> [CategoryOption] {
        categories
    }

    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse {
        categories.removeAll { $0.nys_snw_category_id == id }
        return CategoryDeleteResponse(nys_snw_category_id: id, deleted: true)
    }

    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption {
        let id = nextCategoryId
        nextCategoryId += 1
        let created = CategoryOption(
            nys_snw_category_id: id,
            level_1: category.level_1,
            level_1_name: category.level_1_name,
            level_2: category.level_2,
            level_2_name: category.level_2_name,
            level_3: category.level_3,
            level_4: category.level_4,
            categorization: category.categorization,
            applicability: category.applicability,
            display_label: Self.displayLabel(for: category, fallbackId: id)
        )
        categories.append(created)
        return created
    }

    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption {
        guard let index = categories.firstIndex(where: { $0.nys_snw_category_id == id }) else {
            throw APIError.requestFailed("Category \(id) not found in fixture.")
        }
        let updated = CategoryOption(
            nys_snw_category_id: id,
            level_1: category.level_1,
            level_1_name: category.level_1_name,
            level_2: category.level_2,
            level_2_name: category.level_2_name,
            level_3: category.level_3,
            level_4: category.level_4,
            categorization: category.categorization,
            applicability: category.applicability,
            display_label: Self.displayLabel(for: category, fallbackId: id)
        )
        categories[index] = updated
        return updated
    }

    func fetchCandidates(transactionId: String) async throws -> [MatchCandidateRow] {
        guard matchFixtureEnabled, transactionId == Self.matchFixtureTransactionId else {
            return []
        }
        return [
            MatchCandidateRow(
                email_message_id: Self.matchFixtureEmailId,
                score: 0.92,
                reason_json: nil,
                email_received_at: "2026-04-20T10:00:00+00:00",
                is_selected_by_ai: true,
                is_unmatched_email_priority: false,
                subject: "Your Coffee Roasters receipt",
                from: "receipts@coffee.example.com",
                snippet: "Order Total $16.24",
                mailcart_error: nil
            ),
        ]
    }

    func fetchMessage(emailMessageId: String) async throws -> EmailMessage {
        if matchFixtureEnabled, emailMessageId == Self.matchFixtureEmailId {
            return EmailMessage(
                email_message_id: Self.matchFixtureEmailId,
                subject: "Your Coffee Roasters receipt",
                from: "receipts@coffee.example.com",
                to: "you@example.com",
                received_at: "2026-04-20T10:00:00+00:00",
                html_body: nil,
                text_body: Self.wideReceiptTextBody(orderTotalLine: "Order Total $16.24"),
                snippet: "Order Total $16.24"
            )
        }
        if emailMessageId == Self.searchFixtureEmailId {
            return EmailMessage(
                email_message_id: Self.searchFixtureEmailId,
                subject: "Transit card payment confirmed",
                from: "alerts@transit.example.com",
                to: "you@example.com",
                received_at: "2026-04-18T08:15:00+00:00",
                html_body: nil,
                text_body: "Thanks for riding with us.\nCharge posted: $44.10\nReference: txn_003",
                snippet: "Charge posted: $44.10"
            )
        }
        if emailMessageId == "msg_override_fixture" {
            return EmailMessage(
                email_message_id: "msg_override_fixture",
                subject: "Override candidate fixture",
                from: "override@example.com",
                to: "you@example.com",
                received_at: "2026-04-21T11:00:00+00:00",
                html_body: nil,
                text_body: "This fixture exists for override-action coverage.",
                snippet: "fixture override candidate"
            )
        }
        if emailMessageId.hasPrefix("manual_") {
            return EmailMessage(
                email_message_id: emailMessageId,
                subject: "Manual fixture message",
                from: "manual@example.com",
                to: "you@example.com",
                received_at: "2026-04-22T09:00:00+00:00",
                html_body: nil,
                text_body: "Synthetic manual message for UI testing.",
                snippet: "Synthetic manual message"
            )
        }
        guard matchFixtureEnabled else {
            throw APIError.requestFailed("Unknown fixture email \(emailMessageId)")
        }
        throw APIError.requestFailed("Unknown fixture email \(emailMessageId)")
    }

    func searchMessages(criteria: EmailSearchCriteria, limit: Int) async throws -> EmailSearchResponse {
        let allHits: [EmailSearchHit] = [
            EmailSearchHit(
                email_message_id: Self.searchFixtureEmailId,
                subject: "Transit card payment confirmed",
                from: "alerts@transit.example.com",
                received_at: "2026-04-18T08:15:00+00:00",
                snippet: "Charge posted: $44.10"
            ),
            EmailSearchHit(
                email_message_id: "msg_search_002",
                subject: "Coffee rewards update",
                from: "offers@coffee.example.com",
                received_at: "2026-04-20T12:30:00+00:00",
                snippet: "Your latest Coffee Roasters points summary"
            ),
        ]
        let normalized = criteria.normalized()
        let filtered = allHits.filter { hit in
            guard normalized.hasActiveFilter else { return true }
            if !normalized.subject.isEmpty,
               !(hit.subject ?? "").lowercased().contains(normalized.subject.lowercased()) {
                return false
            }
            if !normalized.sender.isEmpty,
               !(hit.from ?? "").lowercased().contains(normalized.sender.lowercased()) {
                return false
            }
            if !normalized.body.isEmpty,
               !(hit.snippet ?? "").lowercased().contains(normalized.body.lowercased()) {
                return false
            }
            if !normalized.receivedStartDate.isEmpty {
                let receivedDate = String((hit.received_at ?? "").prefix(10))
                if receivedDate < normalized.receivedStartDate { return false }
            }
            if !normalized.receivedEndDate.isEmpty {
                let receivedDate = String((hit.received_at ?? "").prefix(10))
                if receivedDate > normalized.receivedEndDate { return false }
            }
            return true
        }
        return EmailSearchResponse(query: normalized.querySummary, items: Array(filtered.prefix(max(0, limit))))
    }

    func confirmMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        guard let row = rows.first(where: { $0.match?.match_id == matchId }) else {
            throw APIError.requestFailed("Match \(matchId) not found in fixture.")
        }
        return try updateMatch(
            on: row.transaction_id,
            state: "human_confirmed_ai_match",
            selectedBy: "human",
            emailMessageId: row.match?.email_message_id ?? Self.matchFixtureEmailId
        )
    }

    func overrideMatch(matchId: Int, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = note
        guard let row = rows.first(where: { $0.match?.match_id == matchId }) else {
            throw APIError.requestFailed("Match \(matchId) not found in fixture.")
        }
        return try updateMatch(
            on: row.transaction_id,
            state: "human_overrode_ai_match",
            selectedBy: "human",
            emailMessageId: emailMessageId
        )
    }

    func markMatchNoEmail(matchId: Int) async throws -> MatchReviewActionResponse {
        guard let row = rows.first(where: { $0.match?.match_id == matchId }) else {
            throw APIError.requestFailed("Match \(matchId) not found in fixture.")
        }
        return try updateMatch(
            on: row.transaction_id,
            state: "ai_no_match_found",
            selectedBy: "human",
            emailMessageId: nil
        )
    }

    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        guard let index = rows.firstIndex(where: { $0.match?.match_id == matchId }) else {
            throw APIError.requestFailed("Match \(matchId) not found in fixture.")
        }
        let transactionId = rows[index].transaction_id
        rows[index].match = nil
        return MatchReviewActionResponse(
            match_id: matchId,
            transaction_id: transactionId,
            state: "human_confirmed_ai_match",
            selected_by: "human",
            updated_at: "2026-04-23T00:00:00Z"
        )
    }

    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse {
        guard let index = rows.firstIndex(where: { $0.transaction_id == transactionId }) else {
            throw APIError.requestFailed("Transaction \(transactionId) not found in fixture.")
        }
        let matchId = rows[index].match?.match_id ?? 0
        rows[index].match = nil
        return MatchReviewActionResponse(
            match_id: matchId,
            transaction_id: transactionId,
            state: "human_confirmed_ai_match",
            selected_by: "human",
            updated_at: "2026-04-23T00:00:00Z"
        )
    }

    func confirmTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = note
        return try updateMatch(
            on: transactionId,
            state: "human_confirmed_ai_match",
            selectedBy: "human",
            emailMessageId: emailMessageId,
            preserveMatchId: false
        )
    }

    func overrideTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        _ = note
        return try updateMatch(
            on: transactionId,
            state: "human_overrode_ai_match",
            selectedBy: "human",
            emailMessageId: emailMessageId,
            preserveMatchId: false
        )
    }

    func markTransactionNoEmail(transactionId: String) async throws -> MatchReviewActionResponse {
        return try updateMatch(
            on: transactionId,
            state: "ai_no_match_found",
            selectedBy: "human",
            emailMessageId: nil,
            preserveMatchId: false
        )
    }

    func fetchTransactions(_ options: TransactionFetchOptions) async throws -> TransactionListResponse {
        let filtered = filterRows(matching: options)
        if options.countOnly {
            return TransactionListResponse(total: filtered.count, items: [])
        }
        return paginate(filtered, options: options)
    }

    private func filterRows(matching options: TransactionFetchOptions) -> [TransactionRow] {
        let normalizedSearch = options.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedMatchState = options.matchState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            guard rowMatchesClassificationAndMovedState(row, options: options) else { return false }
            guard rowMatchesMatchState(row, normalizedMatchState: normalizedMatchState) else { return false }
            guard rowMatchesAdvancedFilters(row, options: options) else { return false }
            return rowMatchesSearch(row, normalizedSearch: normalizedSearch)
        }
    }

    private func rowMatchesClassificationAndMovedState(_ row: TransactionRow, options: TransactionFetchOptions) -> Bool {
        if options.onlyUnclassified && row.classification != nil { return false }
        if options.onlyUnmovedMatch, let movedAt = row.match?.moved_to_matchy_at, !movedAt.isEmpty { return false }
        return true
    }

    private func rowMatchesMatchState(_ row: TransactionRow, normalizedMatchState: String) -> Bool {
        switch normalizedMatchState {
        case "":
            return true
        case "unmatched":
            return row.match == nil
        case "no_email":
            return row.match?.state == "ai_no_match_found"
        default:
            return row.match?.state == normalizedMatchState
        }
    }

    private func rowMatchesSearch(_ row: TransactionRow, normalizedSearch: String) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }
        return row.description.lowercased().contains(normalizedSearch)
            || row.transaction_id.lowercased().contains(normalizedSearch)
    }

    private func rowMatchesAdvancedFilters(_ row: TransactionRow, options: TransactionFetchOptions) -> Bool {
        let startDate = options.startDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !startDate.isEmpty, row.date < startDate { return false }
        let endDate = options.endDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endDate.isEmpty, row.date > endDate { return false }
        let institutionId = options.institutionId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !institutionId.isEmpty, row.institution_id != institutionId { return false }
        let minAmountText = options.minAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !minAmountText.isEmpty, let minAmount = Decimal(string: minAmountText), row.amount < minAmount { return false }
        let maxAmountText = options.maxAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !maxAmountText.isEmpty, let maxAmount = Decimal(string: maxAmountText), row.amount > maxAmount { return false }
        return true
    }

    private func paginate(_ filtered: [TransactionRow], options: TransactionFetchOptions) -> TransactionListResponse {
        let safeOffset = max(0, min(options.offset, filtered.count))
        let effectiveLimit = min(max(options.limit, 0), max(pageSize, 1))
        let upperBound = min(filtered.count, safeOffset + effectiveLimit)
        let page = Array(filtered[safeOffset..<upperBound])
        let total: Int
        if options.includeTotal {
            total = filtered.count
        } else if page.count < effectiveLimit {
            total = safeOffset + page.count
        } else {
            total = safeOffset + page.count + 1
        }
        return TransactionListResponse(total: total, items: page)
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
