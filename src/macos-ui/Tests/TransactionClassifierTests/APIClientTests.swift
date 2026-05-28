import Foundation
import XCTest
@testable import TransactionClassifier

final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        _ = request
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = URLProtocolStub.requestHandler else {
            XCTFail("requestHandler is not configured")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private func makeClient(baseURL: URL = APIClientTests.testBaseURL) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        return APIClient(baseURL: baseURL, writeToken: "test-write-token", session: session)
    }

    private static let testBaseURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "127.0.0.1"
        components.port = 8787
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    private func makeHTTPResponse(for request: URLRequest, statusCode: Int) throws -> HTTPURLResponse {
        guard let requestURL = request.url else {
            throw APIError.invalidResponse
        }
        guard let response = HTTPURLResponse(url: requestURL, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            throw APIError.invalidResponse
        }
        return response
    }

    private func requestBodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            throw APIError.invalidResponse
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                throw stream.streamError ?? APIError.invalidResponse
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }

    func testFetchCategoriesUsesCategoriesEndpoint() async throws {
        // #R001-T01 #R045-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/categories")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            [{"nys_snw_category_id":101,"level_1":null,"level_1_name":null,"level_2":null,"level_2_name":null,"level_3":null,"level_4":null,"categorization":"Dining","applicability":null,"display_label":"Dining"}]
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        let categories = try await client.fetchCategories()
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.display_label, "Dining")
    }

    func testFetchTransactionsSendsPaginationAndFilterQuery() async throws {
        // #R001-T01 #R001-T03 #R045-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/transactions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["search"], "coffee")
            XCTAssertEqual(query["only_unclassified"], "true")
            XCTAssertEqual(query["limit"], "25")
            XCTAssertEqual(query["offset"], "50")
            XCTAssertEqual(query["include_total"], "true")
            XCTAssertEqual(query["count_only"], "false")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"total":1,"items":[{"transaction_id":"txn_1","account_id":"acc_1","institution_id":"inst_1","account_last_four":"1234","date":"2026-04-18","amount":"10.50","description":"Coffee","status":"posted","transaction_type_code":"card_payment","teller_category":"food","classification":null}]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        let response = try await client.fetchTransactions(
            TransactionFetchOptions(
                search: "coffee",
                onlyUnclassified: true,
                limit: 25,
                offset: 50
            )
        )
        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(response.items.first?.transaction_id, "txn_1")
    }

    func testSaveClassificationsPostsBatchPayload() async throws {
        // #R005-T01 #R045-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/transactions/classifications")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            let body = try self.requestBodyData(request)
            let payload = try JSONDecoder().decode(ClassificationBatchRequest.self, from: body)
            XCTAssertEqual(payload.updates.map(\.transaction_id), ["txn_1", "txn_2"])
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let responseBody = """
            [{"transaction_id":"txn_1","nys_snw_category_id":101,"type":"user","updated_at":"now"},{"transaction_id":"txn_2","nys_snw_category_id":null,"type":"user","updated_at":"now"}]
            """
            return (response, Data(responseBody.utf8))
        }

        let client = makeClient()
        let result = try await client.saveClassifications([
            ClassificationMutation(transaction_id: "txn_1", nys_snw_category_id: 101),
            ClassificationMutation(transaction_id: "txn_2", nys_snw_category_id: nil),
        ])
        XCTAssertEqual(result.count, 2)
    }

    func testNon2xxReturnsServerMessageInRequestFailedError() async {
        // #R010-T01
        URLProtocolStub.requestHandler = { request in
            let response = try self.makeHTTPResponse(for: request, statusCode: 409)
            return (response, Data("conflict: duplicate category".utf8))
        }

        let client = makeClient()
        do {
            _ = try await client.fetchCategories()
            XCTFail("Expected APIError.requestFailed")
        } catch APIError.requestFailed(let message) {
            XCTAssertTrue(message.contains("duplicate category"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCategoryLifecycleUsesCreateUpdateDeleteEndpoints() async throws {
        // #R040-T01 #R040-T02 #R045-T01
        installCategoryLifecycleHandler()
        let client = makeClient()
        let created = try await client.createCategory(petsCategoryRequest(label: "Pets"))
        XCTAssertEqual(created.nys_snw_category_id, 300)
        let updated = try await client.updateCategory(id: 300, category: petsCategoryRequest(label: "Pets Updated"))
        XCTAssertEqual(updated.display_label, "Pets Updated")
        let deleted = try await client.deleteCategory(id: 300)
        XCTAssertTrue(deleted.deleted)
    }

    private func petsCategoryRequest(label: String) -> CategoryMutationRequest {
        CategoryMutationRequest(level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: label, applicability: nil)
    }

    private func installCategoryLifecycleHandler() {
        var callIndex = 0
        URLProtocolStub.requestHandler = { request in
            defer { callIndex += 1 }
            return try Self.categoryLifecycleResponse(for: request, callIndex: callIndex, response: try self.makeHTTPResponse(for: request, statusCode: 200))
        }
    }

    private static func categoryLifecycleResponse(for request: URLRequest, callIndex: Int, response: HTTPURLResponse) throws -> (HTTPURLResponse, Data) {
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
        switch callIndex {
        case 0:
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/categories")
            return (response, Data(petsCreatedJSON.utf8))
        case 1:
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v1/categories/300")
            return (response, Data(petsUpdatedJSON.utf8))
        default:
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/categories/300")
            return (response, Data(petsDeletedJSON.utf8))
        }
    }

    private static let petsCreatedJSON: String = APIClientTestFixtures.petsCreatedJSON
    private static let petsUpdatedJSON: String = APIClientTestFixtures.petsUpdatedJSON
    private static let petsDeletedJSON: String = APIClientTestFixtures.petsDeletedJSON

    func testClearMatchUsesPutClearEndpoints() async throws {
        // #R050-T01
        var callIndex = 0
        URLProtocolStub.requestHandler = { request in
            defer { callIndex += 1 }
            let responseBody = """
            {"match_id":55,"transaction_id":"txn_clear","state":"human_confirmed_ai_match","selected_by":"human","updated_at":"now"}
            """
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            switch callIndex {
            case 0:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/v1/matchy/matches/55/clear")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            default:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/v1/matchy/transactions/txn_clear/clear")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            }
            return (response, Data(responseBody.utf8))
        }

        let client = makeClient()
        let byMatch = try await client.clearMatch(matchId: 55)
        XCTAssertEqual(byMatch.match_id, 55)
        let byTransaction = try await client.clearTransactionMatch(transactionId: "txn_clear")
        XCTAssertEqual(byTransaction.transaction_id, "txn_clear")
    }

    func testOverrideTransactionUsesPutOverrideEndpoint() async throws {
        // #R066-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v1/matchy/transactions/txn_override/override")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            let body = try self.requestBodyData(request)
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(payload?["email_message_id"] as? String, "msg_search_only")
            XCTAssertEqual(payload?["note"] as? String, "manual override")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let responseBody = """
            {"match_id":88,"transaction_id":"txn_override","state":"human_overrode_ai_match","selected_by":"human","updated_at":"now"}
            """
            return (response, Data(responseBody.utf8))
        }

        let client = makeClient()
        let response = try await client.overrideTransaction(
            transactionId: "txn_override",
            emailMessageId: "msg_search_only",
            note: "manual override"
        )
        XCTAssertEqual(response.transaction_id, "txn_override")
        XCTAssertEqual(response.match_id, 88)
    }

    func testSearchMessagesUsesSearchEndpointAndDecodesEnvelope() async throws {
        // #R062-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/matchy/messages/search")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["subject"], "phil")
            XCTAssertEqual(query["limit"], "25")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"query":"subject:phil","items":[{"email_message_id":"msg_phil","subject":"Hello Phil","from":"phil@example.com","received_at":"2026-05-17T12:00:00+00:00","snippet":"preview"}]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        let response = try await client.searchMessages(
            criteria: EmailSearchCriteria(subject: "phil"),
            limit: 25
        )
        XCTAssertEqual(response.query, "subject:phil")
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.email_message_id, "msg_phil")
        XCTAssertEqual(response.items.first?.from, "phil@example.com")
    }

    func testFetchTransactionsEncodesAdvancedFilterQueryParameters() async throws {
        // #R063-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/transactions")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["start_date"], "2026-04-01")
            XCTAssertEqual(query["end_date"], "2026-04-30")
            XCTAssertEqual(query["institution_id"], "inst_alpha")
            XCTAssertEqual(query["min_amount"], "10")
            XCTAssertEqual(query["max_amount"], "100")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"total":0,"items":[]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        _ = try await client.fetchTransactions(
            TransactionFetchOptions(
                startDate: "2026-04-01",
                endDate: "2026-04-30",
                institutionId: "inst_alpha",
                minAmount: "10",
                maxAmount: "100"
            )
        )
    }

    func testSearchMessagesEncodesStructuredCriteriaQueryParameters() async throws {
        // #R064-T01
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/matchy/messages/search")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["subject"], "Transit")
            XCTAssertEqual(query["sender"], "alerts@transit.example.com")
            XCTAssertEqual(query["body"], "Charge")
            XCTAssertEqual(query["start_date"], "2026-04-01")
            XCTAssertEqual(query["end_date"], "2026-04-30")
            XCTAssertEqual(query["limit"], "25")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"query":"subject:Transit","items":[]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        _ = try await client.searchMessages(
            criteria: EmailSearchCriteria(
                subject: "Transit",
                sender: "alerts@transit.example.com",
                body: "Charge",
                receivedStartDate: "2026-04-01",
                receivedEndDate: "2026-04-30"
            ),
            limit: 25
        )
    }

    func testSearchMessagesDateOnlyCriteriaEncodingUsesStructuredFieldsOnly() async throws {
        // #R065-T02
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/matchy/messages/search")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["end_date"], "2026-04-18")
            XCTAssertEqual(query["limit"], "25")
            XCTAssertNil(query["query"])
            XCTAssertNil(query["subject"])
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"query":"to:2026-04-18","items":[]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        _ = try await client.searchMessages(
            criteria: EmailSearchCriteria(receivedEndDate: "2026-04-18"),
            limit: 25
        )
    }

    func testSearchMessagesNormalizesWhitespaceInStructuredCriteria() async throws {
        // #R064-T02
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/matchy/messages/search")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["subject"], "DoorDash order")
            XCTAssertEqual(query["sender"], "receipts@doordash.com")
            XCTAssertEqual(query["body"], "total charged")
            XCTAssertEqual(query["limit"], "25")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"query":"subject:DoorDash order sender:receipts@doordash.com body:total charged","items":[]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        _ = try await client.searchMessages(
            criteria: EmailSearchCriteria(
                subject: "  DoorDash   order ",
                sender: " receipts@doordash.com ",
                body: " total   charged "
            ),
            limit: 25
        )
    }

    func testStructuredCriteriaQuerySummaryMatchesDateOnlyContractExpectation() {
        // #R065-T03
        let criteria = EmailSearchCriteria(receivedStartDate: "2026-04-01")
        XCTAssertEqual(criteria.querySummary, "from:2026-04-01")
    }

    func testMissingWriteTokenThrowsExplicitError() async {
        // #R045-T02
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let clientWithoutToken = APIClient(
            baseURL: Self.testBaseURL,
            writeToken: "",
            session: session
        )
        do {
            _ = try await clientWithoutToken.fetchCategories()
            XCTFail("Expected APIError.missingWriteToken")
        } catch APIError.missingWriteToken {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultWriteTokenFailurePathProducesMissingWriteTokenError() async {
        // #R045-T03
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-client-tests-path-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)

        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", tempPath.path, 1)
        defer {
            setenv("PATH", originalPath, 1)
            try? FileManager.default.removeItem(at: tempPath)
        }

        URLProtocolStub.requestHandler = { _ in
            XCTFail("Expected request to fail before any network call")
            throw APIError.invalidResponse
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = APIClient(baseURL: Self.testBaseURL, session: session)

        do {
            _ = try await client.fetchCategories()
            XCTFail("Expected APIError.missingWriteToken")
        } catch APIError.missingWriteToken {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveClassificationsNon2xxReturnsServerMessage() async {
        // #R010-T02
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = try self.makeHTTPResponse(for: request, statusCode: 422)
            return (response, Data("validation failed: bad payload".utf8))
        }

        let client = makeClient()
        do {
            _ = try await client.saveClassifications([
                ClassificationMutation(transaction_id: "txn_1", nys_snw_category_id: 101),
            ])
            XCTFail("Expected APIError.requestFailed")
        } catch APIError.requestFailed(let message) {
            XCTAssertTrue(message.contains("bad payload"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchTransactionsDateValidationErrorPayloadReturnsFriendlyMessageForStartDate() async {
        // #R010-T03
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/transactions")
            let response = try self.makeHTTPResponse(for: request, statusCode: 422)
            let body = """
            {"detail":[{"type":"string_pattern_mismatch","loc":["query","start_date"],"msg":"String should match pattern"}]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        do {
            _ = try await client.fetchTransactions(TransactionFetchOptions(startDate: "202"))
            XCTFail("Expected APIError.requestFailed")
        } catch APIError.requestFailed(let message) {
            XCTAssertEqual(message, "Expected date format: YYYY-MM-DD for start_date")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchTransactionsDateValidationErrorPayloadReturnsFriendlyMessageForEndDate() async {
        // #R010-T03
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/transactions")
            let response = try self.makeHTTPResponse(for: request, statusCode: 422)
            let body = """
            {"detail":[{"type":"string_pattern_mismatch","loc":["query","end_date"],"msg":"String should match pattern"}]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        do {
            _ = try await client.fetchTransactions(TransactionFetchOptions(endDate: "202"))
            XCTFail("Expected APIError.requestFailed")
        } catch APIError.requestFailed(let message) {
            XCTAssertEqual(message, "Expected date format: YYYY-MM-DD for end_date")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoopbackHostDetectionForTLS() {
        // #R020-T03
        XCTAssertTrue(LocalClassifierTLS.isLoopbackHost("127.0.0.1"))
        XCTAssertTrue(LocalClassifierTLS.isLoopbackHost("localhost"))
        XCTAssertFalse(LocalClassifierTLS.isLoopbackHost("example.com"))
    }

    func testShouldPinLocalCertOnlyForLoopbackHTTPS() {
        // #R020-T04
        guard let loopbackURL = URL(string: "https://127.0.0.1:8787"),
              let remoteURL = URL(string: "https://example.com") else {
            XCTFail("Failed to build test URLs")
            return
        }
        XCTAssertTrue(LocalClassifierTLS.shouldPinLocalCert(for: loopbackURL))
        XCTAssertFalse(LocalClassifierTLS.shouldPinLocalCert(for: remoteURL))
    }

    func testLoadPinnedCertificateFromInstalledDefaultCert() throws {
        // #R020-T05
        let certPath = LocalClassifierTLS.defaultCertPath()
        guard FileManager.default.fileExists(atPath: certPath) else {
            throw XCTSkip("Default classifier TLS cert is not installed at \(certPath)")
        }
        XCTAssertNotNil(LocalClassifierTLS.loadPinnedCertificate(from: certPath))
    }
}
