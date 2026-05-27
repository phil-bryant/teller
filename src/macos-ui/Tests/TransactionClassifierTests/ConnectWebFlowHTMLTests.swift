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

    private func sampleSession(action: ConnectAction) -> ConnectStartSession {
        ConnectStartSession(
            action: action,
            targetKey: action == .add ? "" : "suffix:inst_alpha",
            credentials: ConnectCredentials(
                applicationId: "app_test",
                environment: "development",
                enrollmentId: action == .add ? "" : "enr_alpha"
            )
        )
    }
}
