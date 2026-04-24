import Foundation
import XCTest
@testable import TransactionClassifier

actor MockAPI: ClassificationAPI {
    var categories: [CategoryOption]
    var response: TransactionListResponse
    var pagedResponses: [Int: TransactionListResponse]
    var fetchOffsets: [Int] = []
    var lastSaved: [ClassificationMutation] = []
    init(categories: [CategoryOption], response: TransactionListResponse, pagedResponses: [Int: TransactionListResponse] = [:]) {
        self.categories = categories
        self.response = response
        var merged = pagedResponses
        merged[0] = response
        self.pagedResponses = merged
    }
    func fetchCategories() async throws -> [CategoryOption] { categories }
    func fetchTransactions(search: String, onlyUnclassified: Bool, limit: Int, offset: Int) async throws -> TransactionListResponse {
        fetchOffsets.append(offset)
        return pagedResponses[offset] ?? response
    }
    func recordedFetchOffsets() -> [Int] { fetchOffsets }
    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        lastSaved = updates
        return updates.map { .init(transaction_id: $0.transaction_id, nys_snw_category_id: $0.nys_snw_category_id, type: "user", updated_at: "now") }
    }
}

private func sampleCategory(_ id: Int, _ name: String, applicability: String? = nil) -> CategoryOption {
    .init(nys_snw_category_id: id, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil,
          level_4: nil, categorization: name, applicability: applicability, display_label: name)
}

private func sampleTransaction(_ id: String, date: String = "2026-04-18", classification: TransactionCategory?) -> TransactionRow {
    .init(transaction_id: id, account_id: "acc", date: date, amount: Decimal(10), description: id, status: "posted",
          transaction_type_code: "card_payment", teller_category: "food", classification: classification)
}

final class ClassificationViewModelTests: XCTestCase {
    func testTransactionListDecodesDecimalAmountString() throws {
        let data = """
        {"total":1,"items":[{"transaction_id":"txn_1","account_id":"acc_1","date":"2026-04-18","amount":"33.21",
        "description":"DoorDash","status":"pending","transaction_type_code":"card_payment","teller_category":null,
        "classification":null}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TransactionListResponse.self, from: data)
        XCTAssertEqual(decoded.items.first?.amount, Decimal(string: "33.21"))
    }

    @MainActor
    func testLoadAllPopulatesViewModel() async {
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
    func testSelectedCategoryDidChangeSavesOnlyRowsThatActuallyChange() async {
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
}
