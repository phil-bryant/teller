import Foundation
import XCTest
@testable import TransactionClassifier

final class EmailAmountScrollSupportTests: XCTestCase {
    func testAmountSearchVariantsUsesAbsoluteValueForNegativeDebit() {
        // #R035-T01
        let variants = amountSearchVariants(for: decimal("-15.19"))
        XCTAssertTrue(variants.contains("$15.19"))
        XCTAssertTrue(variants.contains("15.19"))
        XCTAssertTrue(variants.contains("-$15.19"))
        XCTAssertTrue(variants.contains("($15.19)"))
    }

    func testAmountSearchVariantsIncludesCommaGroupingForLargeAmounts() {
        let variants = amountSearchVariants(for: decimal("1234.56"))
        XCTAssertTrue(variants.contains { $0.contains("1,234.56") })
    }

    func testAmountSearchVariantsOrdersLongestFirst() {
        let variants = amountSearchVariants(for: decimal("15.19"))
        guard variants.count >= 2 else {
            XCTFail("Expected multiple variants")
            return
        }
        XCTAssertGreaterThanOrEqual(variants[0].count, variants[1].count)
    }

    func testBestTextLineIndexPrefersOrderTotalOverSubtotal() {
        let text = """
        Sweetgreen receipt
        Subtotal $12.00
        Sales Tax $3.19
        Order Total $15.19
        Thank you
        """
        let index = bestTextLineIndexForAmount(in: text, amount: decimal("-15.19"))
        let lines = text.components(separatedBy: .newlines)
        guard let index else {
            XCTFail("Expected matching line index")
            return
        }
        XCTAssertEqual(lines[index], "Order Total $15.19")
    }

    func testBestTextLineIndexFallsBackToLastMatch() {
        let text = """
        Item A $4.00
        Item B $11.19
        Charged $15.19
        """
        let index = bestTextLineIndexForAmount(in: text, amount: decimal("15.19"))
        let lines = text.components(separatedBy: .newlines)
        guard let index else {
            XCTFail("Expected matching line index")
            return
        }
        XCTAssertEqual(lines[index], "Charged $15.19")
    }

    func testBestTextLineIndexReturnsNilWhenAmountMissing() {
        XCTAssertNil(bestTextLineIndexForAmount(in: "No amounts here", amount: decimal("15.19")))
    }

    func testScrollToAmountJavaScriptIncludesPatterns() {
        let script = scrollToAmountJavaScript(variants: ["$15.19", "15.19"])
        guard let script else {
            XCTFail("Expected scroll JavaScript")
            return
        }
        XCTAssertTrue(script.contains("\"$15.19\""))
        XCTAssertTrue(script.contains("scrollIntoView"))
    }

    func testWrappedEmailHTMLSanitizesActiveContentAndAddsCSP() {
        // #R078-T01
        let html = """
        <meta http-equiv="refresh" content="0;url=https://evil.example.com">
        <form action="https://evil.example.com"></form>
        <iframe src="https://evil.example.com"></iframe>
        <a href="javascript:alert('x')" onclick="alert('x')">click me</a>
        <script>alert("x")</script>
        <p>safe content</p>
        """
        let sanitized = lightlySanitizedEmailHTML(html)
        let wrapped = wrappedEmailHTML(html)
        XCTAssertTrue(wrapped.contains("Content-Security-Policy"))
        XCTAssertFalse(sanitized.contains("<script"))
        XCTAssertFalse(sanitized.contains("<iframe"))
        XCTAssertFalse(sanitized.contains("<form"))
        XCTAssertFalse(sanitized.contains("http-equiv=\"refresh\""))
        XCTAssertFalse(sanitized.contains("onclick="))
        XCTAssertFalse(sanitized.contains("javascript:"))
        XCTAssertTrue(sanitized.contains("href=\"#\""))
        XCTAssertTrue(wrapped.contains("<p>safe content</p>"))
    }
}

private func decimal(
    _ string: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Decimal {
    guard let value = Decimal(string: string) else {
        XCTFail("Invalid decimal literal: \(string)", file: file, line: line)
        return .zero
    }
    return value
}
