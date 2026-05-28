import XCTest
@testable import TransactionClassifier

final class UITestingFixtureClassificationAPITests: XCTestCase {
    func testFixtureCandidatesIncludeActiveMatchedEmailOutsideSeededRun() async throws {
        // #R010-T02
        let key = "TELLER_UI_TEST_MATCH_FIXTURE"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, "1", 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        let api = UITestingFixtureAPI()
        let candidates = try await api.fetchCandidates(transactionId: "txn_007")
        XCTAssertEqual(candidates.map(\.email_message_id), ["msg_overridden_007"])

        let message = try await api.fetchMessage(emailMessageId: "msg_overridden_007")
        XCTAssertEqual(message.email_message_id, "msg_overridden_007")
        XCTAssertNotNil(message.text_body)
    }

    func testFixtureOverridePromotesSearchHitIntoCandidateList() async throws {
        // #R010-T02
        let api = UITestingFixtureAPI()
        _ = try await api.overrideTransaction(transactionId: "txn_003", emailMessageId: "msg_search_001", note: nil)

        let candidates = try await api.fetchCandidates(transactionId: "txn_003")
        XCTAssertEqual(candidates.map(\.email_message_id), ["msg_search_001"])

        let message = try await api.fetchMessage(emailMessageId: "msg_search_001")
        XCTAssertEqual(message.email_message_id, "msg_search_001")
    }
}
