import XCTest
@testable import TransactionClassifier

final class ConnectWebFlowHTMLTests: XCTestCase {
    func testAddSessionHTMLShowsEscapeHint() {
        // #R030-T01
        let html = ConnectWebFlowHTML.render(for: sampleSession(action: .add))
        XCTAssertTrue(html.contains("Press ESC to go back."))
    }

    func testEditSessionHTMLShowsEscapeHint() {
        // #R030-T02
        let html = ConnectWebFlowHTML.render(for: sampleSession(action: .reconnect))
        XCTAssertTrue(html.contains("Press ESC to go back."))
    }

    func testRenderedScriptIncludesSessionNonceBridgePayload() {
        // #R035-T01
        let nonce = "nonce-12345"
        let html = ConnectWebFlowHTML.render(for: sampleSession(action: .add, nonce: nonce))
        XCTAssertTrue(html.contains("const sessionNonce = \"\(nonce)\";"))
        XCTAssertTrue(html.contains("nonce: sessionNonce"))
    }

    func testConnectViewBridgeChecksMainFrameTrustedOriginAndNonce() throws {
        // #R035-T02 #R035-T03
        let source = try Self.loadConnectViewSource()
        XCTAssertTrue(source.contains("guard message.frameInfo.isMainFrame else"))
        XCTAssertTrue(source.contains("trustedBridgeHosts.contains(originHost)"))
        XCTAssertTrue(source.contains("guard nonce == expectedSessionNonce else"))
    }

    private func sampleSession(action: ConnectAction, nonce: String = "test-session-nonce") -> ConnectStartSession {
        ConnectStartSession(
            action: action,
            targetKey: action == .add ? "" : "suffix:inst_alpha",
            credentials: ConnectCredentials(
                applicationId: "app_test",
                environment: "development",
                enrollmentId: action == .add ? "" : "enr_alpha",
                sessionNonce: nonce
            )
        )
    }
}

private extension ConnectWebFlowHTMLTests {
    static func loadConnectViewSource() throws -> String {
        let currentFile = URL(fileURLWithPath: #filePath)
        let packageRoot = currentFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceFile = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("TransactionClassifier")
            .appendingPathComponent("ConnectView.swift")
        return try String(contentsOf: sourceFile, encoding: .utf8)
    }
}
