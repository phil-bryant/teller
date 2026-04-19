import Foundation
import XCTest
@testable import TransactionClassifier

actor MockAPI: ReclassificationAPI {
    var categories: [CategoryOption]
    var response: TransactionListResponse
    var lastSaved: [ClassificationMutation] = []
    init(categories: [CategoryOption], response: TransactionListResponse) {
        self.categories = categories
        self.response = response
    }
    func fetchCategories() async throws -> [CategoryOption] { categories }
    func fetchTransactions(search: String, onlyUnclassified: Bool) async throws -> TransactionListResponse { response }
    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        lastSaved = updates
        return updates.map { .init(transaction_id: $0.transaction_id, nys_snw_category_id: $0.nys_snw_category_id, type: "user", updated_at: "now") }
    }
}

private func sampleCategory(_ id: Int, _ name: String, applicability: String? = nil) -> CategoryOption {
    .init(nys_snw_category_id: id, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil,
          level_4: nil, categorization: name, applicability: applicability, display_label: name)
}

private func sampleTransaction(_ id: String, classification: TransactionCategory?) -> TransactionRow {
    .init(transaction_id: id, account_id: "acc", date: "2026-04-18", amount: Decimal(10), description: id, status: "posted",
          transaction_type_code: "card_payment", teller_category: "food", classification: classification)
}

final class ReclassificationViewModelTests: XCTestCase {
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
        let api = MockAPI(categories: [cat], response: .init(total: 1, items: [sampleTransaction("txn_1", classification: nil)]))
        let vm = ReclassificationViewModel(api: api)
        await vm.loadAll()
        XCTAssertEqual(vm.categories.count, 1)
        XCTAssertEqual(vm.transactions.count, 1)
        XCTAssertTrue(vm.statusText.contains("Loaded"))
    }

    @MainActor
    func testLoadAllFiltersNaApplicabilityCategories() async {
        let include = sampleCategory(1, "Dining", applicability: nil)
        let exclude = sampleCategory(2, "Other", applicability: "N/A")
        let api = MockAPI(categories: [include, exclude], response: .init(total: 1, items: [sampleTransaction("txn_1", classification: nil)]))
        let vm = ReclassificationViewModel(api: api)
        await vm.loadAll()
        XCTAssertEqual(vm.categories.map(\.nys_snw_category_id), [1])
    }

    @MainActor
    func testSaveSelectionUpdatesClassificationOptimistically() async {
        let cat = sampleCategory(22, "Dining")
        let api = MockAPI(categories: [cat], response: .init(total: 1, items: [sampleTransaction("txn_2", classification: nil)]))
        let vm = ReclassificationViewModel(api: api)
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
        let vm = ReclassificationViewModel(api: api)
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
    func testSelectedCategoryDidChangeSavesOnlyRowsThatActuallyChange() async {
        let dining = sampleCategory(22, "Dining")
        let current = TransactionCategory(nys_snw_category_id: 22, display_label: "Dining")
        let rows = [sampleTransaction("txn_1", classification: current), sampleTransaction("txn_2", classification: nil)]
        let api = MockAPI(categories: [dining], response: .init(total: 2, items: rows))
        let vm = ReclassificationViewModel(api: api)
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
