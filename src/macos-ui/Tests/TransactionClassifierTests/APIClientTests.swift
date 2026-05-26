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
        components.scheme = "http"
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
        // #R001-T01 #R045-T01
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
        let response = try await client.fetchTransactions(search: "coffee", onlyUnclassified: true, matchState: "", onlyUnmovedMatch: false, limit: 25, offset: 50)
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
        var callIndex = 0
        URLProtocolStub.requestHandler = { request in
            defer { callIndex += 1 }
            switch callIndex {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/categories")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
                let response = try self.makeHTTPResponse(for: request, statusCode: 200)
                let body = """
                {"nys_snw_category_id":300,"level_1":null,"level_1_name":null,"level_2":null,"level_2_name":null,"level_3":null,"level_4":null,"categorization":"Pets","applicability":null,"display_label":"Pets"}
                """
                return (response, Data(body.utf8))
            case 1:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/v1/categories/300")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
                let response = try self.makeHTTPResponse(for: request, statusCode: 200)
                let body = """
                {"nys_snw_category_id":300,"level_1":null,"level_1_name":null,"level_2":null,"level_2_name":null,"level_3":null,"level_4":null,"categorization":"Pets Updated","applicability":null,"display_label":"Pets Updated"}
                """
                return (response, Data(body.utf8))
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v1/categories/300")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Teller-Write-Token"), "test-write-token")
                let response = try self.makeHTTPResponse(for: request, statusCode: 200)
                let body = """
                {"nys_snw_category_id":300,"deleted":true}
                """
                return (response, Data(body.utf8))
            }
        }

        let client = makeClient()
        let created = try await client.createCategory(.init(level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Pets", applicability: nil))
        XCTAssertEqual(created.nys_snw_category_id, 300)
        let updated = try await client.updateCategory(id: 300, category: .init(level_1: nil, level_1_name: nil, level_2: nil, level_2_name: nil, level_3: nil, level_4: nil, categorization: "Pets Updated", applicability: nil))
        XCTAssertEqual(updated.display_label, "Pets Updated")
        let deleted = try await client.deleteCategory(id: 300)
        XCTAssertTrue(deleted.deleted)
    }

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
            XCTAssertEqual(query["query"], "phil")
            XCTAssertEqual(query["limit"], "25")
            let response = try self.makeHTTPResponse(for: request, statusCode: 200)
            let body = """
            {"query":"phil","items":[{"email_message_id":"msg_phil","subject":"Hello Phil","from":"phil@example.com","received_at":"2026-05-17T12:00:00+00:00","snippet":"preview"}]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        let response = try await client.searchMessages(query: "phil", limit: 25)
        XCTAssertEqual(response.query, "phil")
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.email_message_id, "msg_phil")
        XCTAssertEqual(response.items.first?.from, "phil@example.com")
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
}
