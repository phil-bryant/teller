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
        return ConnectViewModel(api: UITestingFixtureConnectAPI(), setupAPI: UITestingFixtureSetupAPI())
    }
}

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
    private var categories: [CategoryOption] = [
        .init(nys_snw_category_id: 101, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Dining", applicability: nil, display_label: "Dining"),
        .init(nys_snw_category_id: 102, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Utilities", applicability: nil, display_label: "Utilities"),
        .init(nys_snw_category_id: 103, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Transportation", applicability: nil, display_label: "Transportation"),
    ]
    private var rows: [TransactionRow] = [
        .init(transaction_id: "txn_001", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-20", amount: fixtureAmount("16.24"), description: "Coffee Roasters", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_002", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-19", amount: fixtureAmount("88.50"), description: "Electric Utility Co", status: "posted", transaction_type_code: "ach", teller_category: "utilities", classification: .init(nys_snw_category_id: 102, display_label: "Utilities")),
        .init(transaction_id: "txn_003", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-18", amount: fixtureAmount("44.10"), description: "City Transit Card", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_004", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-17", amount: fixtureAmount("22.99"), description: "Corner Market", status: "posted", transaction_type_code: "card_payment", teller_category: "groceries", classification: nil),
        .init(transaction_id: "txn_005", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-16", amount: fixtureAmount("65.00"), description: "Lunch Club", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_006", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-15", amount: fixtureAmount("13.75"), description: "Downtown Parking", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_007", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-14", amount: fixtureAmount("31.45"), description: "Neighborhood Bakery", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_008", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-13", amount: fixtureAmount("55.20"), description: "Gas Station Alpha", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_009", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-12", amount: fixtureAmount("9.99"), description: "Streaming Service", status: "posted", transaction_type_code: "subscription", teller_category: "entertainment", classification: nil),
        .init(transaction_id: "txn_010", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-11", amount: fixtureAmount("124.60"), description: "Grocery Warehouse", status: "posted", transaction_type_code: "card_payment", teller_category: "groceries", classification: nil),
        .init(transaction_id: "txn_011", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-10", amount: fixtureAmount("7.50"), description: "Public Library Cafe", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_012", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-09", amount: fixtureAmount("245.00"), description: "Rent Payment", status: "posted", transaction_type_code: "ach", teller_category: "housing", classification: nil),
        .init(transaction_id: "txn_013", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-08", amount: fixtureAmount("18.30"), description: "Pharmacy Counter", status: "posted", transaction_type_code: "card_payment", teller_category: "health", classification: nil),
        .init(transaction_id: "txn_014", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-07", amount: fixtureAmount("42.00"), description: "Hardware Shop", status: "posted", transaction_type_code: "card_payment", teller_category: "home", classification: nil),
        .init(transaction_id: "txn_015", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-06", amount: fixtureAmount("14.75"), description: "Museum Cafe", status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: nil),
        .init(transaction_id: "txn_016", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-05", amount: fixtureAmount("73.10"), description: "Bookstore Downtown", status: "posted", transaction_type_code: "card_payment", teller_category: "entertainment", classification: nil),
        .init(transaction_id: "txn_017", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-04", amount: fixtureAmount("28.88"), description: "Ride Share Trip", status: "posted", transaction_type_code: "card_payment", teller_category: "transport", classification: nil),
        .init(transaction_id: "txn_018", account_id: "acc_001", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-04-03", amount: fixtureAmount("92.40"), description: "Airline Luggage Fee", status: "posted", transaction_type_code: "card_payment", teller_category: "travel", classification: nil),
    ]

    init(processInfo: ProcessInfo = .processInfo) {
        pageSize = Int(processInfo.environment["TELLER_UI_TEST_PAGE_SIZE"] ?? "2") ?? 2
        matchFixtureEnabled = processInfo.environment["TELLER_UI_TEST_MATCH_FIXTURE"] == "1"
        if matchFixtureEnabled,
           let index = rows.firstIndex(where: { $0.transaction_id == Self.matchFixtureTransactionId }) {
            rows[index].match = TransactionMatchInfo(
                match_id: Self.matchFixtureMatchId,
                email_message_id: Self.matchFixtureEmailId,
                state: "human_confirmed_ai_match",
                ai_confidence: 0.95,
                selected_by: "human",
                moved_to_matchy_at: nil,
                match_count: 1
            )
        }
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

    func searchMessages(query: String, limit: Int) async throws -> EmailSearchResponse {
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
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = allHits.filter { hit in
            guard !normalized.isEmpty else { return true }
            return (hit.subject ?? "").lowercased().contains(normalized)
                || (hit.from ?? "").lowercased().contains(normalized)
                || (hit.snippet ?? "").lowercased().contains(normalized)
                || hit.email_message_id.lowercased().contains(normalized)
        }
        return EmailSearchResponse(query: query, items: Array(filtered.prefix(max(0, limit))))
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

    func fetchTransactions(search: String, onlyUnclassified: Bool, matchState: String, onlyUnmovedMatch: Bool, limit: Int, offset: Int) async throws -> TransactionListResponse {
        _ = matchState; _ = onlyUnmovedMatch
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

    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession {
        if action == .reconnect {
            guard let selectedContext, selectedContext.hasEnrollmentId else {
                throw ConnectServiceError.validation("Selected context has no enrollment_id.")
            }
            return ConnectStartSession(
                action: action,
                targetKey: selectedContext.key,
                applicationId: "app_fixture",
                environment: "development",
                enrollmentId: selectedContext.enrollment_id
            )
        }
        return ConnectStartSession(
            action: action,
            targetKey: "",
            applicationId: "app_fixture",
            environment: "development",
            enrollmentId: ""
        )
    }
}

actor UITestingFixtureSetupAPI: TellerSetupAPI {
    func loadSnapshot() async throws -> TellerSetupSnapshot {
        TellerSetupSnapshot(
            tellerDirectory: "/Users/test/.teller",
            applicationIDPath: "/Users/test/.teller/application_id.txt",
            certificatePath: "/Users/test/.teller/certificate.pem",
            privateKeyPath: "/Users/test/.teller/private_key.pem",
            authTokenPath: "/Users/test/.teller/auth_token.json",
            hasApplicationID: true,
            hasCertificate: true,
            hasPrivateKey: true,
            hasAuthToken: true
        )
    }

    func saveApplicationID(_ applicationID: String) async throws -> String {
        "/Users/test/.teller/application_id.txt"
    }

    func saveAuthToken(_ token: String) async throws -> String {
        "/Users/test/.teller/auth_token.json"
    }

    func runSmokeCheck() async throws -> TellerSmokeCheckResult {
        TellerSmokeCheckResult(
            institutionsHTTPStatus: 200,
            institutionsCount: 1,
            accountsHTTPStatus: 200,
            warningText: ""
        )
    }
}
