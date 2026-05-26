import Foundation
import XCTest
@testable import TransactionClassifier

final class ContentViewRequirementsTests: XCTestCase {
    func testLongListManualSelectionDoesNotRecenterInSmokeSuite() throws {
        // #R050-T01
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains("runLongListManualSelectionDoesNotRecenterScenario"),
            "Smoke suite must include long-list manual selection scroll stability scenario."
        )
    }

    func testAmountVariantsSupportCoffeeRoastersReceiptTotal() {
        // #R035-T02
        guard let amount = Decimal(string: "16.24") else {
            XCTFail("Expected valid decimal literal")
            return
        }
        let variants = amountSearchVariants(for: amount)
        XCTAssertTrue(variants.contains { $0.contains("16.24") })
    }

    @MainActor
    func testBulkDeleteRequiresNonEmptyCategorySelection() async {
        // #R040-T01
        let api = ContentViewRequirementsMockAPI()
        let vm = ClassificationViewModel(api: api)
        await vm.reloadCategories()
        vm.categoryEditorSelection = []
        await vm.deleteSelectedCategories()
        let deleted = await api.recordedDeletedCategoryIds()
        XCTAssertTrue(deleted.isEmpty)
    }

    func testManageCategoriesTabHidesUndoButton() throws {
        // #R060-T02
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains("runManageCategoriesHidesNextUnclassifiedScenario"),
            "Manage Categories smoke must verify undo is hidden on that tab."
        )
        XCTAssertTrue(
            source.contains("XCTAssertFalse(undoControlExists())"),
            "Manage Categories scenario must assert undo-button is absent."
        )
    }

    func testManageCategorySmokeEditReplacesOnlyCategorizationField() throws {
        // #R040-T02
        let source = try Self.loadUITestSource()

        XCTAssertTrue(
            source.contains(#"replaceText(in: uiElement("category-field-categorization"), with: "Dining Updated")"#),
            "Manage Categories smoke edit must clear and replace the populated Categorization field."
        )

        let disallowedReplaceCalls = [
            #"replaceText(in: uiElement("category-field-level-1-name"), with:"#,
            #"replaceText(in: uiElement("category-field-level-2"), with:"#,
            #"replaceText(in: uiElement("category-field-level-2-name"), with:"#,
            #"replaceText(in: uiElement("category-field-level-3"), with:"#,
            #"replaceText(in: uiElement("category-field-level-4"), with:"#,
            #"replaceText(in: uiElement("category-field-applicability"), with:"#,
        ]
        for call in disallowedReplaceCalls {
            XCTAssertFalse(
                source.contains(call),
                "Manage Categories smoke edit should remain paste-only for empty draft fields: \(call)"
            )
        }
    }

    @MainActor
    func testClearMatchRequiresActiveMatchRow() async {
        // #R045-T01
        let row = ContentViewRequirementsTests.sampleTransaction(id: "txn_plain", match: nil)
        let api = ContentViewRequirementsMockAPI(transactions: [row])
        let vm = ClassificationViewModel(api: api)
        await vm.loadAll()
        vm.selection = ["txn_plain"]
        vm.selectionDidChange()
        XCTAssertFalse(vm.canClearSelectedMatch)
    }
}

private actor ContentViewRequirementsMockAPI: ClassificationAPI {
    private var categories: [CategoryOption]
    private let transactions: [TransactionRow]
    private(set) var deletedCategoryIds: [Int] = []

    init(
        categories: [CategoryOption] = [
            .init(nys_snw_category_id: 101, level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Dining", applicability: nil, display_label: "Dining"),
        ],
        transactions: [TransactionRow] = []
    ) {
        self.categories = categories
        self.transactions = transactions
    }

    func fetchCategories() async throws -> [CategoryOption] { categories }

    func fetchTransactions(search: String, onlyUnclassified: Bool, matchState: String, onlyUnmovedMatch: Bool, limit: Int, offset: Int, includeTotal: Bool, countOnly: Bool) async throws -> TransactionListResponse {
        _ = includeTotal; _ = countOnly
        _ = search; _ = onlyUnclassified; _ = matchState; _ = onlyUnmovedMatch; _ = limit; _ = offset
        return TransactionListResponse(total: transactions.count, items: transactions)
    }

    func saveClassifications(_ updates: [ClassificationMutation]) async throws -> [ClassificationWriteResponse] {
        updates.map {
            ClassificationWriteResponse(
                transaction_id: $0.transaction_id,
                nys_snw_category_id: $0.nys_snw_category_id,
                type: "user",
                updated_at: "2026-04-23T00:00:00Z"
            )
        }
    }

    func deleteCategory(id: Int) async throws -> CategoryDeleteResponse {
        deletedCategoryIds.append(id)
        categories.removeAll { $0.nys_snw_category_id == id }
        return CategoryDeleteResponse(nys_snw_category_id: id, deleted: true)
    }

    func recordedDeletedCategoryIds() -> [Int] { deletedCategoryIds }
}

private extension ContentViewRequirementsTests {
    static func loadUITestSource() throws -> String {
        let currentFile = URL(fileURLWithPath: #filePath)
        let packageRoot = currentFile
            .deletingLastPathComponent() // TransactionClassifierTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos-ui package root
        let uiTestFile = packageRoot
            .appendingPathComponent("UITests")
            .appendingPathComponent("TransactionClassifierUITests.swift")
        return try String(contentsOf: uiTestFile, encoding: .utf8)
    }

    static func sampleTransaction(id: String, match: TransactionMatchInfo?) -> TransactionRow {
        TransactionRow(
            transaction_id: id,
            account_id: "acc_001",
            institution_id: "inst_alpha",
            account_last_four: "1111",
            date: "2026-04-20",
            amount: Decimal(string: "16.24") ?? .zero,
            description: "Coffee Roasters",
            status: "posted",
            transaction_type_code: "card_payment",
            teller_category: "food",
            classification: nil,
            match: match
        )
    }
}
