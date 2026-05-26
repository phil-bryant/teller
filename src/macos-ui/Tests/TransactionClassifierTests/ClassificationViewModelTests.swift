import Foundation
import XCTest
@testable import TransactionClassifier

actor MockAPI: ClassificationAPI {
    var categories: [CategoryOption]
    var response: TransactionListResponse
    var pagedResponses: [Int: TransactionListResponse]
    var fetchOffsets: [Int] = []
    var lastSaved: [ClassificationMutation] = []
    var deletedCategoryIds: [Int] = []
    var clearedMatchIds: [Int] = []
    var clearedTransactionIds: [String] = []
    var searchCalls: [(query: String, limit: Int)] = []
    var searchResponse: EmailSearchResponse
    var searchError: Error?
    var saveError: Error?
    init(categories: [CategoryOption], response: TransactionListResponse, pagedResponses: [Int: TransactionListResponse] = [:],
         searchResponse: EmailSearchResponse = .init(query: "", items: []), searchError: Error? = nil, saveError: Error? = nil) {
        self.categories = categories
        self.response = response
        var merged = pagedResponses
        merged[0] = response
        self.pagedResponses = merged
        self.searchResponse = searchResponse
        self.searchError = searchError
        self.saveError = saveError
    }
    func fetchCategories() async throws -> [CategoryOption] { categories }
    func fetchTransactions(search: String, onlyUnclassified: Bool, matchState: String, onlyUnmovedMatch: Bool, limit: Int, offset: Int, includeTotal: Bool, countOnly: Bool) async throws -> TransactionListResponse {
        _ = matchState; _ = onlyUnmovedMatch; _ = includeTotal
        if countOnly { return .init(total: response.total, items: []) }
        fetchOffsets.append(offset)
        return pagedResponses[offset] ?? response
    }
    func recordedFetchOffsets() -> [Int] { fetchOffsets }
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
    func recordedDeletedCategoryIds() -> [Int] { deletedCategoryIds }
    func clearMatch(matchId: Int) async throws -> MatchReviewActionResponse {
        clearedMatchIds.append(matchId)
        return .init(match_id: matchId, transaction_id: "txn_cleared", state: "human_confirmed_ai_match", selected_by: "human", updated_at: "now")
    }
    func clearTransactionMatch(transactionId: String) async throws -> MatchReviewActionResponse {
        clearedTransactionIds.append(transactionId)
        return .init(match_id: 0, transaction_id: transactionId, state: "human_confirmed_ai_match", selected_by: "human", updated_at: "now")
    }
    func recordedClearedMatchIds() -> [Int] { clearedMatchIds }
    func searchMessages(query: String, limit: Int) async throws -> EmailSearchResponse {
        searchCalls.append((query, limit))
        if let searchError { throw searchError }
        return EmailSearchResponse(query: query, items: searchResponse.items)
    }
    func recordedSearchCalls() -> [(query: String, limit: Int)] { searchCalls }
}

private func sampleCategory(_ id: Int, _ name: String, applicability: String? = nil) -> CategoryOption {
    .init(nys_snw_category_id: id, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil,
          level_4: nil, categorization: name, applicability: applicability, display_label: name)
}

private func sampleTransaction(_ id: String, date: String = "2026-04-18", classification: TransactionCategory?) -> TransactionRow {
    .init(transaction_id: id, account_id: "acc", date: date, amount: Decimal(10), description: id, status: "posted",
          transaction_type_code: "card_payment", teller_category: "food", classification: classification)
}

private func sampleTransactionWithMatch(id: String, matchId: Int, emailId: String, confidence: Double, count: Int,
                                        state: String = "ai_match_confident", classification: TransactionCategory? = nil) -> TransactionRow {
    let match = TransactionMatchInfo(match_id: matchId, email_message_id: emailId, state: state,
                                     ai_confidence: confidence, selected_by: "ai", moved_to_matchy_at: nil, match_count: count)
    return TransactionRow(transaction_id: id, account_id: "acc", date: "2026-05-06", amount: Decimal(200),
                          description: id, status: "posted", transaction_type_code: "card_payment",
                          teller_category: nil, classification: classification, match: match)
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
        let api = MockAPI(categories: [cat], response: firstPage, pagedResponses: [2: secondPage])
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
    func testClearSelectedMatchCallsApiAndReloads() async {
        // #R035-T01
        let matched = sampleTransactionWithMatch(
            id: "txn_matched", matchId: 42, emailId: "msg_a", confidence: 0.9, count: 1,
            state: "human_confirmed_ai_match"
        )
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
    func testSearchMailcartPopulatesResultsFromApi() async {
        // #R040-T01
        let hit = EmailSearchHit(email_message_id: "msg_phil", subject: "Hello Phil", from: "phil@example.com",
                                 received_at: "2026-05-17T12:00:00+00:00", snippet: "preview")
        let api = MockAPI(categories: [], response: .init(total: 0, items: []),
                          searchResponse: .init(query: "phil", items: [hit]))
        let vm = ClassificationViewModel(api: api)
        vm.mailcartSearchQuery = "phil"
        await vm.searchMailcartIfNeeded()
        XCTAssertEqual(vm.mailcartSearchResults.map(\.email_message_id), ["msg_phil"])
        XCTAssertTrue(vm.mailcartSearchErrorText.isEmpty)
        let calls = await api.recordedSearchCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.query, "phil")
    }

    @MainActor
    func testSearchMailcartSurfacesApiFailure() async {
        // #R040-T02
        let api = MockAPI(categories: [], response: .init(total: 0, items: []),
                          searchError: APIError.requestFailed("search failed"))
        let vm = ClassificationViewModel(api: api)
        vm.mailcartSearchQuery = "phil"
        await vm.searchMailcartIfNeeded()
        XCTAssertTrue(vm.mailcartSearchResults.isEmpty)
        XCTAssertTrue(vm.mailcartSearchErrorText.contains("search failed"))
    }

    @MainActor
    func testSaveSelectionRollsBackOnApiFailure() async {
        // #R010-T01
        let cat = sampleCategory(22, "Dining")
        let api = MockAPI(
            categories: [cat],
            response: .init(total: 1, items: [sampleTransaction("txn_2", classification: nil)]),
            saveError: APIError.requestFailed("save failed")
        )
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
