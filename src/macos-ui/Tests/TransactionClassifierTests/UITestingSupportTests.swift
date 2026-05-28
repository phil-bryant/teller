import Darwin
import XCTest
@testable import TransactionClassifier

final class UITestingSupportTests: XCTestCase {
    func testDetectAppLaunchModeMatchesProcessInputs() {
        // #R001-T01
        let processInfo = ProcessInfo.processInfo
        let expected: AppLaunchMode = (processInfo.arguments.contains("--ui-testing")
            || processInfo.environment["TELLER_UI_TEST_MODE"] == "1") ? .uiTesting : .normal
        let actual = detectAppLaunchMode(processInfo: processInfo)
        switch (actual, expected) {
        case (.normal, .normal), (.uiTesting, .uiTesting):
            break
        default:
            XCTFail("Expected launch mode \(expected) but found \(actual).")
        }
    }

    @MainActor
    func testBuildDefaultViewModelsUseFixturesWhenUITestingEnabled() async {
        // #R005-T01
        let key = "TELLER_UI_TEST_MODE"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, "1", 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }

        let classificationVM = buildDefaultViewModel()
        await classificationVM.loadAll()
        XCTAssertEqual(classificationVM.categories.count, 3)
        XCTAssertEqual(classificationVM.transactions.first?.transaction_id, "txn_001")

        let connectVM = buildDefaultConnectViewModel()
        await connectVM.loadAll()
        XCTAssertEqual(connectVM.contexts.count, 2)
        XCTAssertEqual(connectVM.selectedContextKey, "default")
    }

    func testClassificationFixtureReturnsSeededData() async throws {
        // #R010-T01
        let api = UITestingFixtureAPI()
        let categories = try await api.fetchCategories()
        XCTAssertEqual(categories.map(\.nys_snw_category_id), [101, 102, 103])

        let page = try await api.fetchTransactions(
            TransactionFetchOptions(
                search: "",
                onlyUnclassified: true,
                limit: 100,
                offset: 0,
                includeTotal: true,
                countOnly: false
            )
        )
        XCTAssertEqual(page.total, 17)
        XCTAssertEqual(page.items.first?.transaction_id, "txn_001")
    }

    func testClassificationFixtureSurfacesActiveMatchEmailAsCandidate() async throws {
        // #R010-T02
        let key = "TELLER_UI_TEST_MATCH_FIXTURE"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, "1", 1)
        defer {
            if let previous { setenv(key, previous, 1) } else { unsetenv(key) }
        }

        let api = UITestingFixtureAPI()
        // txn_007 carries an overridden match (msg_overridden_007) that is not a seeded run candidate.
        let candidates = try await api.fetchCandidates(transactionId: "txn_007")
        XCTAssertEqual(candidates.map(\.email_message_id), ["msg_overridden_007"])
        let message = try await api.fetchMessage(emailMessageId: "msg_overridden_007")
        XCTAssertEqual(message.email_message_id, "msg_overridden_007")
        XCTAssertNotNil(message.text_body)
    }

    func testClassificationFixtureSurfacesOverriddenSearchEmailAsCandidate() async throws {
        // #R010-T02
        let api = UITestingFixtureAPI()
        // txn_003 starts unmatched; overriding with a searched email must make it the candidate.
        _ = try await api.overrideTransaction(transactionId: "txn_003", emailMessageId: "msg_search_001", note: nil)
        let candidates = try await api.fetchCandidates(transactionId: "txn_003")
        XCTAssertEqual(candidates.map(\.email_message_id), ["msg_search_001"])
        let message = try await api.fetchMessage(emailMessageId: "msg_search_001")
        XCTAssertEqual(message.email_message_id, "msg_search_001")
    }

    func testConnectFixtureAddAppendsContext() async throws {
        // #R015-T01
        let api = UITestingFixtureConnectAPI()
        _ = try await api.storeToken(
            ConnectStoreTokenRequest(
                token: "token_fixture",
                enrollmentId: "enr_gamma",
                action: ConnectAction.add.rawValue,
                targetKey: "",
                institutionIdHint: "inst_gamma"
            )
        )
        let contexts = try await api.fetchContexts()
        XCTAssertEqual(contexts.count, 3)
        XCTAssertTrue(contexts.contains { $0.key == "suffix:inst_gamma" && $0.enrollment_id == "enr_gamma" })
    }

    func testSetupFixtureReturnsReadySnapshot() async throws {
        // #R020-T01
        let api = UITestingFixtureSetupAPI()
        let snapshot = try await api.loadSnapshot()
        XCTAssertTrue(snapshot.hasApplicationID)
        XCTAssertTrue(snapshot.hasCertificate)
        XCTAssertTrue(snapshot.hasPrivateKey)
        XCTAssertTrue(snapshot.hasAuthToken)
    }
}
