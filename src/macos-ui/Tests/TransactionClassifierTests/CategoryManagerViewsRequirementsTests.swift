import Foundation
import XCTest

final class CategoryManagerViewsRequirementsTests: XCTestCase {
    func testManageCategoryBulkDeleteScenarioExercisedInSmokeSuite() throws {
        // #R040-T01
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains("runManageCategoryDeleteScenario"),
            "Smoke suite must include manage-category bulk delete scenario."
        )
        XCTAssertTrue(
            source.contains(#"uiElement("category-bulk-delete-button").click()"#),
            "Manage category delete scenario must exercise the bulk-delete button."
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
}

private extension CategoryManagerViewsRequirementsTests {
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
}
