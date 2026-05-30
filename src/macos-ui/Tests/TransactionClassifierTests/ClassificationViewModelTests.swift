import Foundation
import XCTest
@testable import TransactionClassifier

struct FetchTransactionsCall: Sendable {
    let includeTotal: Bool
    let countOnly: Bool
    let limit: Int
}

struct MockAPIConfig {
    var categories: [CategoryOption]
    var response: TransactionListResponse
    var fetchError: Error?
    var pagedResponses: [Int: TransactionListResponse] = [:]
    var sequentialResponses: [TransactionListResponse] = []
    var candidatesByTransactionId: [String: [MatchCandidateRow]] = [:]
    var candidatesDelayNanoseconds: UInt64 = 0
    var searchResponse: EmailSearchResponse = EmailSearchResponse(query: "", items: [])
    var searchError: Error?
    var saveError: Error?
    var confirmTransactionCandidateError: Error?
    var overrideTransactionCandidateError: Error?
    var overrideMatchResponseTransactionId: String?
    var markTransactionNoEmailError: Error?
}

actor MockAPI: ClassificationAPI {
    var categories: [CategoryOption]
    var response: TransactionListResponse
    var fetchError: Error?
    var pagedResponses: [Int: TransactionListResponse]
    var sequentialResponses: [TransactionListResponse]
    var fetchOffsets: [Int] = []
    var lastFetchOptions: TransactionFetchOptions?
    var fetchTransactionsCalls: [FetchTransactionsCall] = []
    var candidatesFetchCount = 0
    var candidatesByTransactionId: [String: [MatchCandidateRow]] = [:]
    var candidatesDelayNanoseconds: UInt64 = 0
    var lastSaved: [ClassificationMutation] = []
    var deletedCategoryIds: [Int] = []
    var createdCategoryRequests: [CategoryMutationRequest] = []
    var updatedCategoryRequests: [(id: Int, request: CategoryMutationRequest)] = []
    var clearedMatchIds: [Int] = []
    var clearedTransactionIds: [String] = []
    var confirmedMatchIds: [Int] = []
    var confirmedMatchCalls: [(matchId: Int, emailMessageId: String?, note: String?)] = []
    var confirmedTransactionCandidateCalls: [(transactionId: String, emailMessageId: String, note: String?)] = []
    var overriddenMatchCalls: [(matchId: Int, emailMessageId: String, note: String?)] = []
    var overriddenTransactionCalls: [(transactionId: String, emailMessageId: String, note: String?)] = []
    var overriddenTransactionCandidateCalls: [(transactionId: String, emailMessageId: String, note: String?)] = []
    var markedNoEmailMatchIds: [Int] = []
    var markedNoEmailTransactionIds: [String] = []
    var searchCalls: [(criteria: EmailSearchCriteria, limit: Int)] = []
    var searchResponse: EmailSearchResponse
    var searchError: Error?
    var saveError: Error?
    var confirmTransactionCandidateError: Error?
    var overrideTransactionCandidateError: Error?
    var overrideMatchResponseTransactionId: String?
    var markTransactionNoEmailError: Error?

    init(_ config: MockAPIConfig) {
        self.categories = config.categories
        self.response = config.response
        self.fetchError = config.fetchError
        var merged = config.pagedResponses
        merged[0] = config.response
        self.pagedResponses = merged
        self.sequentialResponses = config.sequentialResponses
        self.candidatesByTransactionId = config.candidatesByTransactionId
        self.candidatesDelayNanoseconds = config.candidatesDelayNanoseconds
        self.searchResponse = config.searchResponse
        self.searchError = config.searchError
        self.saveError = config.saveError
        self.confirmTransactionCandidateError = config.confirmTransactionCandidateError
        self.overrideTransactionCandidateError = config.overrideTransactionCandidateError
        self.overrideMatchResponseTransactionId = config.overrideMatchResponseTransactionId
        self.markTransactionNoEmailError = config.markTransactionNoEmailError
    }

    init(categories: [CategoryOption], response: TransactionListResponse) {
        self.init(MockAPIConfig(categories: categories, response: response))
    }
    func fetchCategories() async throws -> [CategoryOption] { categories }
    func fetchTransactions(_ options: TransactionFetchOptions) async throws -> TransactionListResponse {
        if let fetchError { throw fetchError }
        lastFetchOptions = options
        fetchTransactionsCalls.append(
            FetchTransactionsCall(includeTotal: options.includeTotal, countOnly: options.countOnly, limit: options.limit)
        )
        if options.countOnly {
            let total = sequentialResponses.first?.total ?? response.total
            return .init(total: total, items: [])
        }
        fetchOffsets.append(options.offset)
        if options.offset == 0, !sequentialResponses.isEmpty {
            let next = sequentialResponses.removeFirst()
            response = next
            pagedResponses[0] = next
            return next
        }
        return pagedResponses[options.offset] ?? response
    }
    func fetchCandidates(transactionId: String) async throws -> [MatchCandidateRow] {
        candidatesFetchCount += 1
        if candidatesDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: candidatesDelayNanoseconds)
        }
        return candidatesByTransactionId[transactionId] ?? []
    }
    func recordedFetchOffsets() -> [Int] { fetchOffsets }
    func recordedFetchTransactionsCalls() -> [FetchTransactionsCall] { fetchTransactionsCalls }
    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        lastSaved = updates
        if let saveError { throw saveError }
        return updates.map { .init(transaction_id: $0.transaction_id, nys_snw_category_id: $0.nys_snw_category_id, type: "user", updated_at: "now") }
    }
    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse {
        deletedCategoryIds.append(id)
        categories.removeAll { $0.nys_snw_category_id == id }
        return .init(nys_snw_category_id: id, deleted: true)
    }
    func createCategory(_ category: CategoryMutationRequest) async throws -> CategoryOption {
        createdCategoryRequests.append(category)
        let newId = (categories.map(\.nys_snw_category_id).max() ?? 0) + 1
        let display = category.categorization ?? category.level_4 ?? category.level_3 ?? category.level_2_name ?? category.level_1_name ?? "New Category"
        let saved = CategoryOption(
            nys_snw_category_id: newId,
            level_1: category.level_1,
            level_1_name: category.level_1_name,
            level_2: category.level_2,
            level_2_name: category.level_2_name,
            level_3: category.level_3,
            level_4: category.level_4,
            categorization: category.categorization,
            applicability: category.applicability,
            display_label: display
        )
        categories.append(saved)
        return saved
    }
    func updateCategory(id: Int, category: CategoryMutationRequest) async throws -> CategoryOption {
        updatedCategoryRequests.append((id, category))
        guard let idx = categories.firstIndex(where: { $0.nys_snw_category_id == id }) else {
            throw APIError.requestFailed("category \(id) not found")
        }
        let existing = categories[idx]
        let saved = CategoryOption(
            nys_snw_category_id: id,
            level_1: category.level_1 ?? existing.level_1,
            level_1_name: category.level_1_name ?? existing.level_1_name,
            level_2: category.level_2 ?? existing.level_2,
            level_2_name: category.level_2_name ?? existing.level_2_name,
            level_3: category.level_3 ?? existing.level_3,
            level_4: category.level_4 ?? existing.level_4,
            categorization: category.categorization ?? existing.categorization,
            applicability: category.applicability ?? existing.applicability,
            display_label: category.categorization ?? existing.display_label
        )
        categories[idx] = saved
        return saved
    }
    func recordedDeletedCategoryIds() -> [Int] { deletedCategoryIds }
    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        clearedMatchIds.append(matchId)
        return .init(match_id: matchId, transaction_id: "txn_cleared", state: "human_confirmed_ai_match", selected_by: "human", updated_at: "now")
    }
    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse {
        clearedTransactionIds.append(transactionId)
        return .init(match_id: 0, transaction_id: transactionId, state: "human_confirmed_ai_match", selected_by: "human", updated_at: "now")
    }
    func confirmMatch(matchId: Int, emailMessageId: String?, note: String?) async throws -> MatchReviewActionResponse {
        confirmedMatchCalls.append((matchId, emailMessageId, note))
        confirmedMatchIds.append(matchId)
        return .init(match_id: matchId, transaction_id: "txn_confirmed", state: "human_confirmed_ai_match", selected_by: "human", updated_at: "now")
    }
    func confirmTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        confirmedTransactionCandidateCalls.append((transactionId, emailMessageId, note))
        if let confirmTransactionCandidateError { throw confirmTransactionCandidateError }
        return .init(match_id: 0, transaction_id: transactionId, state: "human_confirmed_ai_match", selected_by: "human", updated_at: "now")
    }
    func overrideMatch(matchId: Int, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        overriddenMatchCalls.append((matchId, emailMessageId, note))
        let transactionId = overrideMatchResponseTransactionId
            ?? response.items.first(where: { $0.match?.match_id == matchId })?.transaction_id
            ?? "txn_overridden"
        return .init(match_id: matchId, transaction_id: transactionId, state: "human_overrode_ai_match", selected_by: "human", updated_at: "now")
    }
    func overrideTransactionCandidate(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        overriddenTransactionCandidateCalls.append((transactionId, emailMessageId, note))
        if let overrideTransactionCandidateError { throw overrideTransactionCandidateError }
        return .init(match_id: 0, transaction_id: transactionId, state: "human_overrode_ai_match", selected_by: "human", updated_at: "now")
    }
    func overrideTransaction(transactionId: String, emailMessageId: String, note: String?) async throws -> MatchReviewActionResponse {
        overriddenTransactionCalls.append((transactionId, emailMessageId, note))
        return .init(match_id: 0, transaction_id: transactionId, state: "human_overrode_ai_match", selected_by: "human", updated_at: "now")
    }
    func markMatchNoEmail(matchId: Int) async throws -> MatchReviewActionResponse {
        markedNoEmailMatchIds.append(matchId)
        return .init(match_id: matchId, transaction_id: "txn_no_email", state: "ai_no_match_found", selected_by: "human", updated_at: "now")
    }
    func markTransactionNoEmail(transactionId: String) async throws -> MatchReviewActionResponse {
        markedNoEmailTransactionIds.append(transactionId)
        if let markTransactionNoEmailError { throw markTransactionNoEmailError }
        return .init(match_id: 0, transaction_id: transactionId, state: "ai_no_match_found", selected_by: "human", updated_at: "now")
    }
    func recordedClearedMatchIds() -> [Int] { clearedMatchIds }
    func recordedConfirmedMatchIds() -> [Int] { confirmedMatchIds }
    func recordedConfirmMatchCalls() -> [(matchId: Int, emailMessageId: String?, note: String?)] { confirmedMatchCalls }
    func recordedConfirmTransactionCandidateCalls() -> [(transactionId: String, emailMessageId: String, note: String?)] {
        confirmedTransactionCandidateCalls
    }
    func recordedOverriddenMatchCalls() -> [(matchId: Int, emailMessageId: String, note: String?)] {
        overriddenMatchCalls
    }
    func recordedOverrideTransactionCandidateCalls() -> [(transactionId: String, emailMessageId: String, note: String?)] {
        overriddenTransactionCandidateCalls
    }
    func recordedOverrideTransactionCalls() -> [(transactionId: String, emailMessageId: String, note: String?)] {
        overriddenTransactionCalls
    }
    func searchMessages(criteria: EmailSearchCriteria, limit: Int) async throws -> EmailSearchResponse {
        searchCalls.append((criteria, limit))
        if let searchError { throw searchError }
        return EmailSearchResponse(query: criteria.querySummary, items: searchResponse.items)
    }
    func recordedSearchCalls() -> [(criteria: EmailSearchCriteria, limit: Int)] { searchCalls }
    func recordedLastFetchOptions() -> TransactionFetchOptions? { lastFetchOptions }
    func recordedCreatedCategoryRequests() -> [CategoryMutationRequest] { createdCategoryRequests }
}

private func sampleCategory(_ id: Int, _ name: String, applicability: String? = nil) -> CategoryOption {
    CategoryOption(nys_snw_category_id: id, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: name, applicability: applicability, display_label: name)
}

private func sampleTransaction(_ id: String, date: String = "2026-04-18", classification: TransactionCategory?) -> TransactionRow {
    TransactionRow(transaction_id: id, account_id: "acc", institution_id: "inst_alpha", account_last_four: "1111", date: date, amount: Decimal(10), description: id, status: "posted", transaction_type_code: "card_payment", teller_category: "food", classification: classification)
}

private struct SampleMatchSpec {
    let id: String
    let matchId: Int
    let emailId: String
    let confidence: Double
    let count: Int
    var state: String = "ai_match_confident"
    var classification: TransactionCategory?
}

private func sampleTransactionWithMatch(_ spec: SampleMatchSpec) -> TransactionRow {
    let match = TransactionMatchInfo(match_id: spec.matchId, email_message_id: spec.emailId, state: spec.state, ai_confidence: spec.confidence, selected_by: "ai", moved_to_matchy_at: nil, match_count: spec.count)
    return TransactionRow(transaction_id: spec.id, account_id: "acc", institution_id: "inst_alpha", account_last_four: "1111", date: "2026-05-06", amount: Decimal(200), description: spec.id, status: "posted", transaction_type_code: "card_payment", teller_category: nil, classification: spec.classification, match: match)
}

private func sampleTransactionWithMatch(id: String, matchId: Int, emailId: String, confidence: Double, count: Int) -> TransactionRow {
    sampleTransactionWithMatch(SampleMatchSpec(id: id, matchId: matchId, emailId: emailId, confidence: confidence, count: count))
}

private func sampleTransactionWithNoEmailMatch(
    id: String,
    matchId: Int,
    count: Int = 1,
    classification: TransactionCategory? = nil
) -> TransactionRow {
    let match = TransactionMatchInfo(
        match_id: matchId,
        email_message_id: nil,
        state: "ai_no_match_found",
        ai_confidence: nil,
        selected_by: "human",
        moved_to_matchy_at: nil,
        match_count: count
    )
    return TransactionRow(
        transaction_id: id,
        account_id: "acc",
        institution_id: "inst_alpha",
        account_last_four: "1111",
        date: "2026-05-06",
        amount: Decimal(200),
        description: id,
        status: "posted",
        transaction_type_code: "card_payment",
        teller_category: nil,
        classification: classification,
        match: match
    )
}

private func sampleCandidate(emailId: String, isSelectedByAi: Bool) -> MatchCandidateRow {
    MatchCandidateRow(email_message_id: emailId, score: 0.5, reason_json: nil, email_received_at: nil,
                      is_selected_by_ai: isSelectedByAi, is_unmatched_email_priority: false,
                      subject: nil, from: nil, snippet: nil, mailcart_error: nil)
}

final class ClassificationViewModelTests: XCTestCase {
    func testTransactionListDecodesDecimalAmountString() throws {
        let payload = """
        {"total":1,"items":[{"transaction_id":"txn_1","account_id":"acc_1","date":"2026-04-18","amount":"33.21",
        "description":"DoorDash","status":"pending","transaction_type_code":"card_payment","teller_category":null,
        "classification":null}]}
        """
        let data = try XCTUnwrap(payload.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TransactionListResponse.self, from: data)
        XCTAssertEqual(decoded.items.first?.amount, Decimal(string: "33.21"))
    }

    @MainActor
    func testTransactionListProfilerDisabledUnlessEnvSet() {
        // #R080-T01
        XCTAssertFalse(TransactionListProfiler.isEnabled)
    }

    @MainActor
    func testLoadAllUsesFastFirstFetchParameters() async {
        // #R001-T02
        let api = MockAPI(
            categories: [sampleCategory(1, "Dining")],
            response: .init(total: 2, items: [sampleTransaction("txn_1", classification: nil)])
        )
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        let calls = await api.recordedFetchTransactionsCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].includeTotal, false)
        XCTAssertEqual(calls[0].countOnly, false)
        XCTAssertEqual(calls[0].limit, 150)
    }

    @MainActor
    func testReselectingTransactionReloadsCandidatesWhenPaneWasCleared() async {
        let txn = sampleTransactionWithMatch(id: "txn_1", matchId: 1, emailId: "msg_a", confidence: 0.9, count: 1)
        let candidate = sampleCandidate(emailId: "msg_a", isSelectedByAi: true)
        var config = MockAPIConfig(categories: [], response: .init(total: 1, items: [txn]))
        config.candidatesByTransactionId = ["txn_1": [candidate]]
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [txn]
        vm.selection = ["txn_1"]
        await vm.selectedTransactionDidChange()
        XCTAssertEqual(vm.candidates.map(\.email_message_id), ["msg_a"])

        vm.candidates = []
        await vm.selectedTransactionDidChange()
        XCTAssertEqual(vm.candidates.map(\.email_message_id), ["msg_a"])
        let fetches = await api.candidatesFetchCount
        XCTAssertGreaterThanOrEqual(fetches, 2)
    }

    @MainActor
    func testLoadAllReloadsCandidatesForCurrentSelection() async {
        let txn = sampleTransactionWithMatch(id: "txn_1", matchId: 1, emailId: "msg_a", confidence: 0.9, count: 1)
        let candidate = sampleCandidate(emailId: "msg_a", isSelectedByAi: true)
        var config = MockAPIConfig(categories: [sampleCategory(1, "Dining")], response: .init(total: 1, items: [txn]))
        config.candidatesByTransactionId = ["txn_1": [candidate]]
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.selection = ["txn_1"]
        await vm.loadAll()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.candidates.map(\.email_message_id), ["msg_a"])
        let fetches = await api.candidatesFetchCount
        XCTAssertGreaterThanOrEqual(fetches, 1)
    }

    @MainActor
    func testLoadAllClearsBusyBeforeCandidatesFetchCompletes() async throws {
        // #R001-T03
        let matchTxn = sampleTransactionWithMatch(id: "txn_1", matchId: 1, emailId: "msg", confidence: 0.9, count: 1)
        var config = MockAPIConfig(
            categories: [sampleCategory(1, "Dining")],
            response: .init(total: 1, items: [matchTxn])
        )
        config.candidatesDelayNanoseconds = 200_000_000
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.selection = ["txn_1"]
        await vm.loadAll()
        XCTAssertFalse(vm.busy)
        try await Task.sleep(nanoseconds: 250_000_000)
        let candidateFetches = await api.candidatesFetchCount
        XCTAssertGreaterThanOrEqual(candidateFetches, 1)
    }

    @MainActor
    func testRefreshTransactionTotalRunsCountOnlyFetch() async throws {
        // #R075-T01
        let api = MockAPI(
            categories: [sampleCategory(1, "Dining")],
            response: .init(total: 99, items: [sampleTransaction("txn_1", classification: nil)])
        )
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        let calls = await api.recordedFetchTransactionsCalls()
        XCTAssertTrue(calls.contains { $0.countOnly && $0.includeTotal })
        XCTAssertEqual(vm.totalTransactions, 99)
    }

    @MainActor
    func testLoadAllPopulatesViewModel() async {
        // #R001-T01
        let cat = sampleCategory(11, "Utilities")
        let rows = [
            sampleTransaction("txn_1", date: "2026-04-17", classification: nil),
            sampleTransaction("txn_2", date: "2026-04-19", classification: nil),
        ]
        let api = MockAPI(categories: [cat], response: .init(total: 2, items: rows))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        XCTAssertEqual(vm.categories.count, 1)
        XCTAssertEqual(vm.transactions.count, 2)
        XCTAssertEqual(vm.statusText, "Loaded 2 transactions (2026-04-17 to 2026-04-19)")
    }

    @MainActor
    func testLoadAllFiltersNaApplicabilityCategories() async {
        let include = sampleCategory(1, "Dining", applicability: nil)
        let exclude = sampleCategory(2, "Other", applicability: "N/A")
        let api = MockAPI(categories: [include, exclude], response: .init(total: 1, items: [sampleTransaction("txn_1", classification: nil)]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        XCTAssertEqual(vm.categories.map(\.nys_snw_category_id), [1])
    }

    @MainActor
    func testSaveSelectionUpdatesClassificationOptimistically() async {
        // #R010-T01
        let cat = sampleCategory(22, "Dining")
        let api = MockAPI(categories: [cat], response: .init(total: 1, items: [sampleTransaction("txn_2", classification: nil)]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_2"]
        vm.selectedCategoryId = 22
        await vm.saveSelection()
        XCTAssertEqual(vm.transactions.first?.classification?.nys_snw_category_id, 22)
        XCTAssertEqual(vm.undoStack.count, 1)
    }

    @MainActor
    func testNextUnclassifiedMovesSelection() async {
        // #R015-T01
        let cat = sampleCategory(77, "Housing")
        let items = [
            sampleTransaction("txn_a", classification: .init(nys_snw_category_id: 77, display_label: "Housing")),
            sampleTransaction("txn_b", classification: nil),
            sampleTransaction("txn_c", classification: nil),
        ]
        let api = MockAPI(categories: [cat], response: .init(total: 3, items: items))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_a"]
        vm.nextUnclassified()
        XCTAssertEqual(vm.selection, ["txn_b"])
    }

    func testRankedCategoryOptionsRanksExactBest() {
        let options = rankedCategoryOptions(
            query: "utilities",
            categories: [sampleCategory(10, "Utilities"), sampleCategory(11, "Utility Services"), sampleCategory(12, "Dining")]
        )
        XCTAssertEqual(options.first?.categoryId, 10)
    }

    func testRankedCategoryOptionsSupportsFuzzySubsequenceMatches() {
        let options = rankedCategoryOptions(
            query: "gst",
            categories: [sampleCategory(1, "Dining"), sampleCategory(2, "Gas Station"), sampleCategory(3, "Groceries")]
        )
        XCTAssertEqual(options.first?.categoryId, 2)
    }

    @MainActor
    func testLoadMoreAppendsAdditionalTransactions() async {
        // #R020-T01
        let cat = sampleCategory(11, "Utilities")
        let firstPage = TransactionListResponse(total: 4, items: [
            sampleTransaction("txn_1", date: "2026-04-20", classification: nil),
            sampleTransaction("txn_2", date: "2026-04-19", classification: nil),
        ])
        let secondPage = TransactionListResponse(total: 4, items: [
            sampleTransaction("txn_3", date: "2026-04-18", classification: nil),
            sampleTransaction("txn_4", date: "2026-04-17", classification: nil),
        ])
        var config = MockAPIConfig(categories: [cat], response: firstPage)
        config.pagedResponses = [2: secondPage]
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        await vm.loadMore()
        XCTAssertEqual(vm.transactions.map(\.transaction_id), ["txn_1", "txn_2", "txn_3", "txn_4"])
        XCTAssertEqual(vm.statusText, "Loaded 4 transactions (2026-04-17 to 2026-04-20)")
        XCTAssertFalse(vm.canLoadMore)
        let offsets = await api.recordedFetchOffsets()
        XCTAssertEqual(offsets, [0, 2])
    }

    @MainActor
    func testRedundantSaveSelectionDoesNotPushIdentityUndoEntry() async {
        // #R005-T01
        let cat = sampleCategory(22, "Dining")
        let api = MockAPI(categories: [cat], response: .init(total: 1, items: [sampleTransaction("txn_1", classification: nil)]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_1"]
        vm.selectedCategoryId = 22
        await vm.saveSelection()
        XCTAssertEqual(vm.undoStack.count, 1)
        await vm.saveSelection()
        XCTAssertEqual(vm.undoStack.count, 1, "Re-applying an already-assigned category must not push a duplicate undo entry")
        await vm.undoLast()
        XCTAssertNil(vm.transactions.first?.classification, "A single undo should restore the prior unclassified state")
        XCTAssertTrue(vm.undoStack.isEmpty)
    }

    @MainActor
    func testTransactionMatchInfoExposesAggregateCounts() {
        // After the merge to the unified `/v1/transactions` endpoint, dedupe lives in the backend
        // (the LEFT JOIN LATERAL picks one representative match row per transaction) and the row
        // model carries `match.match_count` so the UI can render a "N emails" badge.
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [
            sampleTransactionWithMatch(id: "txn_cursor", matchId: 436, emailId: "msg_c", confidence: 0.95, count: 3),
            sampleTransactionWithMatch(id: "txn_other", matchId: 437, emailId: "msg_x", confidence: 0.80, count: 1),
        ]
        XCTAssertEqual(vm.matchedEmailCount(for: "txn_cursor"), 3)
        XCTAssertEqual(vm.matchedEmailCount(for: "txn_other"), 1)
        XCTAssertEqual(vm.matchedEmailCount(for: "txn_unknown"), 0)
    }

    @MainActor
    func testActiveEmailIdsForSelectedTransactionUnionsRepresentativeAndAiPickedCandidates() {
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [
            sampleTransactionWithMatch(id: "txn_cursor", matchId: 436, emailId: "msg_c", confidence: 0.95, count: 3),
            sampleTransactionWithMatch(id: "txn_other", matchId: 437, emailId: "msg_x", confidence: 0.80, count: 1),
        ]
        vm.candidates = [
            sampleCandidate(emailId: "msg_a", isSelectedByAi: true),
            sampleCandidate(emailId: "msg_b", isSelectedByAi: true),
            sampleCandidate(emailId: "msg_c", isSelectedByAi: true),
            sampleCandidate(emailId: "msg_other_unrelated", isSelectedByAi: false),
        ]
        vm.selection = ["txn_cursor"]
        XCTAssertEqual(vm.activeEmailIdsForSelectedTransaction, ["msg_a", "msg_b", "msg_c"])
        vm.selection = ["txn_other"]
        // Candidates list is stale (still for txn_cursor), so the active set comes from the
        // match's representative email only; in practice selectedTransactionDidChange clears it.
        XCTAssertTrue(vm.activeEmailIdsForSelectedTransaction.contains("msg_x"))
        vm.selection = []
        XCTAssertTrue(vm.activeEmailIdsForSelectedTransaction.isEmpty || vm.activeEmailIdsForSelectedTransaction == Set(vm.candidates.filter(\.is_selected_by_ai).map(\.email_message_id)))
    }

    @MainActor
    func testCanOverrideSelectedMatchUsesActiveSetNotJustRepresentative() {
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [
            sampleTransactionWithMatch(id: "txn_cursor", matchId: 436, emailId: "msg_a", confidence: 0.95, count: 2),
        ]
        vm.candidates = [
            sampleCandidate(emailId: "msg_a", isSelectedByAi: true),
            sampleCandidate(emailId: "msg_b", isSelectedByAi: true),
        ]
        vm.selection = ["txn_cursor"]
        // Picking msg_b (also AI-active for this transaction) must NOT be considered an override target.
        vm.selectedCandidateId = "msg_b"
        XCTAssertFalse(vm.canOverrideSelectedMatch)
        // Picking a brand new email IS an override target.
        vm.selectedCandidateId = "msg_zzz"
        XCTAssertTrue(vm.canOverrideSelectedMatch)
    }

    @MainActor
    func testCanConfirmSelectedMatchWhenCandidateExistsWithoutMatchRow() {
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [sampleTransaction("txn_unmatched", classification: nil)]
        vm.candidates = [sampleCandidate(emailId: "msg_ai", isSelectedByAi: true)]
        vm.selection = ["txn_unmatched"]
        vm.selectedCandidateId = "msg_ai"
        XCTAssertNil(vm.selectedMatchId)
        XCTAssertTrue(vm.canConfirmSelectedMatch)
        XCTAssertTrue(vm.canOverrideSelectedMatch)
        XCTAssertTrue(vm.canMarkSelectedMatchNoEmail)
        XCTAssertFalse(vm.canClearSelectedMatch)
    }

    @MainActor
    func testCanConfirmAndOverrideRequireLatestCandidateForUnmatchedTransaction() {
        // #R110-T01
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [sampleTransaction("txn_unmatched", classification: nil)]
        vm.candidates = []
        vm.mailcartSearchResults = [
            EmailSearchHit(email_message_id: "msg_search_only", subject: "Tacombi", from: "noreply@doordash.com", received_at: "2026-05-24T00:00:00+00:00", snippet: "receipt")
        ] // Simulates selecting from ad-hoc search results, not latest candidates.
        vm.selection = ["txn_unmatched"]
        vm.selectedCandidateId = "msg_search_only"
        XCTAssertTrue(vm.isOverrideTargetSearchHitOnly)
        XCTAssertFalse(vm.canConfirmSelectedMatch)
        XCTAssertTrue(vm.canOverrideSelectedMatch)
    }

    @MainActor
    func testCanConfirmSelectedMatchStaysEnabledWhenSelectedEmailWouldBeOverride() {
        // #R105-T01
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [
            sampleTransactionWithMatch(id: "txn_cursor", matchId: 1716, emailId: "msg_active", confidence: 0.95, count: 1),
        ]
        vm.selection = ["txn_cursor"]
        vm.selectedCandidateId = "msg_different"
        XCTAssertTrue(vm.canConfirmSelectedMatch)
        XCTAssertTrue(vm.canOverrideSelectedMatch)
    }

    @MainActor
    func testCanConfirmSelectedMatchIsEnabledForNoEmailMatchWithCandidateSelection() {
        // #R117-T01
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [
            sampleTransactionWithNoEmailMatch(id: "txn_no_email", matchId: 1717),
        ]
        vm.candidates = [sampleCandidate(emailId: "msg_candidate", isSelectedByAi: true)]
        vm.selection = ["txn_no_email"]
        vm.selectedCandidateId = "msg_candidate"
        XCTAssertTrue(vm.canConfirmSelectedMatch)
    }

    @MainActor
    func testCanClearSelectedMatchWhenActiveMatchExists() {
        // #R035-T02
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [
            sampleTransactionWithMatch(id: "txn_matched", matchId: 42, emailId: "msg_a", confidence: 0.9, count: 1),
        ]
        vm.selection = ["txn_matched"]
        XCTAssertTrue(vm.canClearSelectedMatch)
    }

    @MainActor
    func testConfirmSelectedMatchRecoversWhenTransactionSnapshotIsStale() async {
        // #R100-T01
        let stale = sampleTransaction("txn_stale", classification: nil)
        let refreshed = sampleTransactionWithMatch(id: "txn_stale", matchId: 88, emailId: "msg_existing", confidence: 0.9, count: 1)
        var config = MockAPIConfig(categories: [], response: .init(total: 1, items: [stale]))
        config.sequentialResponses = [
            .init(total: 1, items: [stale]),
            .init(total: 1, items: [refreshed]),
        ]
        config.confirmTransactionCandidateError = APIError.requestFailed(
            "{\"detail\":\"Transaction already has an active match; use /v1/matchy/matches/{match_id} mutation endpoints\"}"
        )
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_stale"]
        vm.selectedCandidateId = "msg_candidate"

        await vm.confirmSelectedMatch()

        let transactionCalls = await api.recordedConfirmTransactionCandidateCalls()
        let matchCalls = await api.recordedConfirmedMatchIds()
        XCTAssertEqual(transactionCalls.count, 1)
        XCTAssertEqual(matchCalls, [88])
        XCTAssertEqual(vm.matchReviewStatusText, "Confirmed match 88")
        XCTAssertTrue(vm.matchReviewErrorText.isEmpty)
    }

    @MainActor
    func testOverrideSelectedMatchRecoversWhenTransactionSnapshotIsStale() async {
        // #R100-T02
        let stale = sampleTransaction("txn_stale", classification: nil)
        let refreshed = sampleTransactionWithMatch(id: "txn_stale", matchId: 91, emailId: "msg_existing", confidence: 0.92, count: 1)
        var config = MockAPIConfig(categories: [], response: .init(total: 1, items: [stale]))
        config.sequentialResponses = [
            .init(total: 1, items: [stale]),
            .init(total: 1, items: [refreshed]),
        ]
        config.overrideTransactionCandidateError = APIError.requestFailed(
            "{\"detail\":\"Transaction already has an active match; use /v1/matchy/matches/{match_id} mutation endpoints\"}"
        )
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_stale"]
        vm.selectedCandidateId = "msg_override"

        await vm.overrideSelectedMatch()

        let transactionCalls = await api.recordedOverrideTransactionCalls()
        let matchCalls = await api.recordedOverriddenMatchCalls()
        XCTAssertEqual(transactionCalls.count, 1)
        XCTAssertEqual(transactionCalls.first?.transactionId, "txn_stale")
        XCTAssertEqual(transactionCalls.first?.emailMessageId, "msg_override")
        XCTAssertEqual(matchCalls.count, 0)
        XCTAssertEqual(vm.matchReviewStatusText, "Assigned email to txn_stale")
        XCTAssertTrue(vm.matchReviewErrorText.isEmpty)
    }

    @MainActor
    func testConfirmSelectedMatchDoesNotOverrideWhenDifferentEmailIsSelected() async {
        // #R105-T02
        var matchedSpec = SampleMatchSpec(id: "txn_matched", matchId: 1716, emailId: "msg_active", confidence: 0.9, count: 1)
        matchedSpec.state = "ai_candidate_uncertain"
        let matched = sampleTransactionWithMatch(matchedSpec)
        let api = MockAPI(categories: [], response: .init(total: 1, items: [matched]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_matched"]
        vm.selectedCandidateId = "msg_tacombi"

        await vm.confirmSelectedMatch()

        let confirmed = await api.recordedConfirmedMatchIds()
        let overridden = await api.recordedOverriddenMatchCalls()
        XCTAssertEqual(confirmed, [1716])
        XCTAssertTrue(overridden.isEmpty)
        XCTAssertEqual(vm.matchReviewStatusText, "Confirmed match 1716")
        XCTAssertTrue(vm.matchReviewErrorText.isEmpty)
    }

    @MainActor
    func testConfirmSelectedMatchForNoEmailStateUsesConfirmSemantics() async {
        // #R117-T02
        let noEmail = sampleTransactionWithNoEmailMatch(id: "txn_no_email", matchId: 1718)
        let api = MockAPI(categories: [], response: .init(total: 1, items: [noEmail]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_no_email"]
        vm.candidates = [sampleCandidate(emailId: "msg_candidate", isSelectedByAi: true)]
        vm.selectedCandidateId = "msg_candidate"

        await vm.confirmSelectedMatch()

        let confirmed = await api.recordedConfirmedMatchIds()
        let confirmCalls = await api.recordedConfirmMatchCalls()
        let overridden = await api.recordedOverriddenMatchCalls()
        let transactionCalls = await api.recordedConfirmTransactionCandidateCalls()
        XCTAssertEqual(confirmed, [1718])
        XCTAssertEqual(confirmCalls.count, 1)
        XCTAssertEqual(confirmCalls.first?.matchId, 1718)
        XCTAssertEqual(confirmCalls.first?.emailMessageId, "msg_candidate")
        XCTAssertTrue(overridden.isEmpty)
        XCTAssertTrue(transactionCalls.isEmpty)
        XCTAssertEqual(vm.matchReviewStatusText, "Confirmed match 1718")
        XCTAssertTrue(vm.matchReviewErrorText.isEmpty)
    }

    @MainActor
    func testConfirmSelectedMatchRejectsSearchOnlyEmailForUnmatchedTransaction() async {
        // #R110-T02
        let api = MockAPI(categories: [], response: .init(total: 1, items: [sampleTransaction("txn_unmatched", classification: nil)]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_unmatched"]
        vm.candidates = []
        vm.mailcartSearchResults = [
            EmailSearchHit(email_message_id: "msg_search_only", subject: "Tacombi", from: "noreply@doordash.com", received_at: "2026-05-24T00:00:00+00:00", snippet: "receipt")
        ]
        vm.selectedCandidateId = "msg_search_only"

        await vm.confirmSelectedMatch()

        let transactionCalls = await api.recordedConfirmTransactionCandidateCalls()
        XCTAssertTrue(transactionCalls.isEmpty)
        XCTAssertEqual(vm.matchReviewStatusText, "Match confirm failed")
        XCTAssertTrue(vm.matchReviewErrorText.contains("not a candidate"))
    }

    @MainActor
    func testOverrideSelectedMatchAllowsSearchOnlyEmailForUnmatchedTransaction() async {
        // #R110-T03
        let api = MockAPI(categories: [], response: .init(total: 1, items: [sampleTransaction("txn_unmatched", classification: nil)]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_unmatched"]
        vm.candidates = []
        vm.mailcartSearchResults = [
            EmailSearchHit(email_message_id: "msg_search_only", subject: "Tacombi", from: "noreply@doordash.com", received_at: "2026-05-24T00:00:00+00:00", snippet: "receipt")
        ]
        vm.selectedCandidateId = "msg_search_only"

        await vm.overrideSelectedMatch()

        let candidateCalls = await api.recordedOverrideTransactionCandidateCalls()
        let overrideAnyCalls = await api.recordedOverrideTransactionCalls()
        XCTAssertTrue(candidateCalls.isEmpty)
        XCTAssertEqual(overrideAnyCalls.count, 1)
        XCTAssertEqual(overrideAnyCalls.first?.transactionId, "txn_unmatched")
        XCTAssertEqual(overrideAnyCalls.first?.emailMessageId, "msg_search_only")
        XCTAssertTrue(vm.matchReviewStatusText.contains("Assigned email to"))
        XCTAssertTrue(vm.matchReviewErrorText.isEmpty)
    }

    @MainActor
    func testOverrideSelectedMatchFailsWhenMatchIdTargetsDifferentTransaction() async {
        // #R115-T01
        var matchedSpec = SampleMatchSpec(id: "txn_matched", matchId: 1716, emailId: "msg_active", confidence: 0.9, count: 1)
        matchedSpec.state = "ai_no_match_found"
        let matched = sampleTransactionWithMatch(matchedSpec)
        var config = MockAPIConfig(categories: [], response: .init(total: 1, items: [matched]))
        config.overrideMatchResponseTransactionId = "txn_other"
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_matched"]
        vm.selectedCandidateId = "msg_search_only"

        await vm.overrideSelectedMatch()

        let matchCalls = await api.recordedOverriddenMatchCalls()
        let transactionCalls = await api.recordedOverrideTransactionCalls()
        XCTAssertEqual(matchCalls.count, 1)
        XCTAssertEqual(transactionCalls.count, 0)
        XCTAssertEqual(vm.matchReviewStatusText, "Match override failed")
        XCTAssertTrue(vm.matchReviewErrorText.contains("different transaction"))
    }

    @MainActor
    func testClearSelectedMatchCallsApiAndReloads() async {
        // #R035-T01
        var matchedSpec = SampleMatchSpec(id: "txn_matched", matchId: 42, emailId: "msg_a", confidence: 0.9, count: 1)
        matchedSpec.state = "human_confirmed_ai_match"
        let matched = sampleTransactionWithMatch(matchedSpec)
        let api = MockAPI(categories: [], response: .init(total: 1, items: [matched]))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_matched"]
        await vm.clearSelectedMatch()
        let clearedIds = await api.recordedClearedMatchIds()
        XCTAssertEqual(clearedIds, [42])
        XCTAssertEqual(vm.matchReviewStatusText, "Cleared match 42 for txn_cleared")
        XCTAssertTrue(vm.matchReviewErrorText.isEmpty)
    }

    @MainActor
    func testSelectedCategoryDidChangeSavesOnlyRowsThatActuallyChange() async {
        // #R005-T01
        let dining = sampleCategory(22, "Dining")
        let current = TransactionCategory(nys_snw_category_id: 22, display_label: "Dining")
        let rows = [sampleTransaction("txn_1", classification: current), sampleTransaction("txn_2", classification: nil)]
        let api = MockAPI(categories: [dining], response: .init(total: 2, items: rows))
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_1", "txn_2"]
        vm.selectedCategoryId = 22
        await vm.selectedCategoryDidChange()
        let saved = await api.lastSaved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.transaction_id, "txn_2")
        XCTAssertEqual(vm.transactions.first(where: { $0.transaction_id == "txn_2" })?.classification?.nys_snw_category_id, 22)
    }

    @MainActor
    func testDeleteSelectedCategoriesRemovesAllSelectedRows() async {
        // #R030-T01
        let categories = [sampleCategory(11, "Utilities"), sampleCategory(12, "Dining"), sampleCategory(13, "Travel")]
        let api = MockAPI(categories: categories, response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        await vm.reloadCategories()
        vm.categoryEditorSelection = [11, 12]
        await vm.deleteSelectedCategories()
        let deleted = await api.recordedDeletedCategoryIds()
        XCTAssertEqual(deleted, [11, 12])
        XCTAssertTrue(vm.categoryEditorSelection.isEmpty)
        XCTAssertEqual(vm.allCategories.map(\.nys_snw_category_id), [13])
        XCTAssertEqual(vm.categoryEditorStatusText, "Deleted 2 categories.")
    }

    @MainActor
    func testSaveCategoryDraftCreatesCategoryAndSyncsEditorSelection() async {
        // #R085-T01
        let categories = [sampleCategory(11, "Utilities"), sampleCategory(12, "Dining")]
        let api = MockAPI(categories: categories, response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        await vm.reloadCategories()
        vm.beginNewCategoryDraft()
        vm.categoryEditorDraft.categorization = "Streaming"
        vm.categoryEditorDraft.applicability = "CARD"
        await vm.saveCategoryDraft()

        let created = await api.recordedCreatedCategoryRequests()
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.categorization, "Streaming")
        XCTAssertFalse(vm.categoryEditorSelection.isEmpty)
        let savedId = try? XCTUnwrap(vm.categoryEditorSelection.first)
        XCTAssertEqual(vm.categoryEditorPrimarySelectionId, savedId)
        XCTAssertTrue(vm.allCategories.contains(where: { $0.nys_snw_category_id == savedId }))
        XCTAssertEqual(vm.categoryEditorStatusText, "Saved category \(savedId ?? -1).")
        XCTAssertTrue(vm.categoryEditorErrorText.isEmpty)
    }

    @MainActor
    func testSearchMailcartPopulatesResultsFromApi() async {
        // #R040-T01 #R095-T01
        let hit = EmailSearchHit(email_message_id: "msg_phil", subject: "Hello Phil", from: "phil@example.com",
                                 received_at: "2026-05-17T12:00:00+00:00", snippet: "preview")
        var config = MockAPIConfig(categories: [], response: .init(total: 0, items: []))
        config.searchResponse = .init(query: "subject:phil", items: [hit])
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.mailcartSearchSubject = "phil"
        await vm.searchMailcartIfNeeded()
        XCTAssertEqual(vm.mailcartSearchResults.map(\.email_message_id), ["msg_phil"])
        XCTAssertTrue(vm.mailcartSearchErrorText.isEmpty)
        let calls = await api.recordedSearchCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.criteria.subject, "phil")
    }

    @MainActor
    func testMailcartSearchResultsPersistWhenTransactionSelectionChanges() async {
        // #R116-T01
        let hit = EmailSearchHit(email_message_id: "msg_doordash", subject: "DoorDash", from: "noreply@doordash.com",
                                 received_at: "2026-05-25T12:00:00+00:00", snippet: "receipt")
        let txnA = sampleTransaction("txn_a", classification: nil)
        let txnB = sampleTransaction("txn_b", classification: nil)
        var config = MockAPIConfig(categories: [], response: .init(total: 2, items: [txnA, txnB]))
        config.searchResponse = .init(query: "body:doordash", items: [hit])
        config.candidatesByTransactionId = ["txn_a": [], "txn_b": []]
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [txnA, txnB]
        vm.mailcartSearchBody = "doordash"
        await vm.searchMailcartIfNeeded()
        XCTAssertEqual(vm.mailcartSearchResults.map(\.email_message_id), ["msg_doordash"])

        vm.selection = ["txn_a"]
        await vm.selectedTransactionDidChange()
        XCTAssertEqual(vm.mailcartSearchResults.map(\.email_message_id), ["msg_doordash"])
        XCTAssertEqual(vm.mailcartSearchBody, "doordash")

        vm.selection = ["txn_b"]
        await vm.selectedTransactionDidChange()
        XCTAssertEqual(vm.mailcartSearchResults.map(\.email_message_id), ["msg_doordash"])
    }

    @MainActor
    func testSelectingSearchHitDuringCandidateLoadIsNotClobberedAndOverrideUsesIt() async {
        // #R116-T02
        let hit = EmailSearchHit(email_message_id: "msg_search_only", subject: "Tacombi", from: "noreply@doordash.com",
                                 received_at: "2026-05-24T00:00:00+00:00", snippet: "receipt")
        let txn = sampleTransaction("txn_unmatched", classification: nil)
        var config = MockAPIConfig(categories: [], response: .init(total: 1, items: [txn]))
        config.searchResponse = .init(query: "body:doordash", items: [hit])
        // Latest run returns an unrelated AI candidate that would otherwise auto-select.
        config.candidatesByTransactionId = ["txn_unmatched": [sampleCandidate(emailId: "msg_ai_candidate", isSelectedByAi: true)]]
        config.candidatesDelayNanoseconds = 80_000_000
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.transactions = [txn]
        vm.mailcartSearchBody = "doordash"
        await vm.searchMailcartIfNeeded()
        XCTAssertEqual(vm.mailcartSearchResults.map(\.email_message_id), ["msg_search_only"])

        vm.selection = ["txn_unmatched"]
        let loadTask = Task { await vm.selectedTransactionDidChange() }
        // Simulate the user clicking the persisted search hit while candidates are still loading.
        try? await Task.sleep(nanoseconds: 20_000_000)
        vm.selectedCandidateId = "msg_search_only"
        await loadTask.value

        XCTAssertEqual(vm.selectedCandidateId, "msg_search_only")

        await vm.overrideSelectedMatch()
        let overrideAnyCalls = await api.recordedOverrideTransactionCalls()
        let candidateCalls = await api.recordedOverrideTransactionCandidateCalls()
        XCTAssertTrue(candidateCalls.isEmpty)
        XCTAssertEqual(overrideAnyCalls.count, 1)
        XCTAssertEqual(overrideAnyCalls.first?.emailMessageId, "msg_search_only")
        XCTAssertEqual(overrideAnyCalls.first?.transactionId, "txn_unmatched")
    }

    @MainActor
    func testSearchMailcartSurfacesApiFailure() async {
        // #R040-T02 #R095-T02
        var config = MockAPIConfig(categories: [], response: .init(total: 0, items: []))
        config.searchError = APIError.requestFailed("search failed")
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.mailcartSearchBody = "phil"
        await vm.searchMailcartIfNeeded()
        XCTAssertTrue(vm.mailcartSearchResults.isEmpty)
        XCTAssertTrue(vm.mailcartSearchErrorText.contains("search failed"))
    }

    @MainActor
    func testSearchMailcartNormalizesWhitespaceBeforeApiCall() async {
        // #R095-T03
        var config = MockAPIConfig(categories: [], response: .init(total: 0, items: []))
        config.searchResponse = .init(query: "subject:DoorDash order sender:receipts@doordash.com body:total charged", items: [])
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        vm.mailcartSearchSubject = "  DoorDash   order "
        vm.mailcartSearchSender = " receipts@doordash.com "
        vm.mailcartSearchBody = " total   charged "
        await vm.searchMailcartIfNeeded()
        let calls = await api.recordedSearchCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.criteria.subject, "DoorDash order")
        XCTAssertEqual(calls.first?.criteria.sender, "receipts@doordash.com")
        XCTAssertEqual(calls.first?.criteria.body, "total charged")
    }

    @MainActor
    func testAdvancedTransactionFiltersForwardToFetchOptions() async {
        // #R090-T01
        let api = MockAPI(categories: [], response: .init(total: 0, items: []))
        let vm = ClassificationViewModel(api: api)
        vm.transactionStartDate = "2026-04-01"
        vm.transactionEndDate = "2026-04-30"
        vm.transactionInstitutionId = "inst_alpha"
        vm.transactionMinAmount = "10"
        vm.transactionMaxAmount = "100"
        await vm.loadAll()
        let options = await api.recordedLastFetchOptions()
        XCTAssertEqual(options?.startDate, "2026-04-01")
        XCTAssertEqual(options?.endDate, "2026-04-30")
        XCTAssertEqual(options?.institutionId, "inst_alpha")
        XCTAssertEqual(options?.minAmount, "10")
        XCTAssertEqual(options?.maxAmount, "100")
    }

    @MainActor
    func testLoadAllSurfacesFriendlyDateFormatErrorTextForTransactionFilters() async {
        // #R090-T03
        var startConfig = MockAPIConfig(categories: [], response: .init(total: 0, items: []))
        startConfig.fetchError = APIError.requestFailed("Expected date format: YYYY-MM-DD for start_date")
        let startVM = ClassificationViewModel(api: MockAPI(startConfig))
        await startVM.loadAll()
        XCTAssertTrue(startVM.errorText.contains("Expected date format: YYYY-MM-DD"))
        XCTAssertTrue(startVM.errorText.contains("start_date"))

        var endConfig = MockAPIConfig(categories: [], response: .init(total: 0, items: []))
        endConfig.fetchError = APIError.requestFailed("Expected date format: YYYY-MM-DD for end_date")
        let endVM = ClassificationViewModel(api: MockAPI(endConfig))
        await endVM.loadAll()
        XCTAssertTrue(endVM.errorText.contains("Expected date format: YYYY-MM-DD"))
        XCTAssertTrue(endVM.errorText.contains("end_date"))
    }

    @MainActor
    func testSaveSelectionRollsBackOnApiFailure() async {
        // #R010-T01
        let cat = sampleCategory(22, "Dining")
        var config = MockAPIConfig(
            categories: [cat],
            response: .init(total: 1, items: [sampleTransaction("txn_2", classification: nil)])
        )
        config.saveError = APIError.requestFailed("save failed")
        let api = MockAPI(config)
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_2"]
        vm.selectedCategoryId = 22
        await vm.saveSelection()
        XCTAssertNil(vm.transactions.first?.classification)
        XCTAssertEqual(vm.rowState["txn_2"], .failed("save failed"))
        XCTAssertTrue(vm.undoStack.isEmpty)
    }
}
