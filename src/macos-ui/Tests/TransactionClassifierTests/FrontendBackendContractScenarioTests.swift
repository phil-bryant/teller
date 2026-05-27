import Foundation
import XCTest
@testable import TransactionClassifier

final class FrontendBackendContractScenarioTests: XCTestCase {
    private struct ContractScenarios: Decodable {
        struct ClassificationApi: Decodable {
            struct Transactions: Decodable {
                struct AdvancedFilters: Decodable {
                    let query: [String: String]
                }

                let advancedFilters: AdvancedFilters
            }

            struct MessageSearch: Decodable {
                struct DateOnlyScenario: Decodable {
                    let query: [String: String]
                    let effective_query: String
                }

                let dateOnlyEnd: DateOnlyScenario
                let dateOnlyStart: DateOnlyScenario
            }

            let transactions: Transactions
            let messageSearch: MessageSearch
        }

        let classificationApi: ClassificationApi
    }

    private static let testBaseURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "127.0.0.1"
        components.port = 8787
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    private func loadScenarios() throws -> ContractScenarios {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent() // TransactionClassifierTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos-ui
            .deletingLastPathComponent() // src
            .deletingLastPathComponent() // repo root
        let scenarioPath = repoRoot
            .appendingPathComponent("tests")
            .appendingPathComponent("contracts")
            .appendingPathComponent("frontend_backend_contract_scenarios.json")
        let data = try Data(contentsOf: scenarioPath)
        return try JSONDecoder().decode(ContractScenarios.self, from: data)
    }

    private func makeClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        return APIClient(baseURL: Self.testBaseURL, writeToken: "test-write-token", session: session)
    }

    private func makeHTTPResponse(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url else {
            throw APIError.invalidResponse
        }
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            throw APIError.invalidResponse
        }
        return response
    }

    func testTransactionAdvancedFilterSerializationMatchesContractCorpus() async throws {
        // #R065-T01
        let scenarios = try loadScenarios()
        let expectedQuery = scenarios.classificationApi.transactions.advancedFilters.query
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/transactions")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["start_date"], expectedQuery["start_date"])
            XCTAssertEqual(query["end_date"], expectedQuery["end_date"])
            XCTAssertEqual(query["institution_id"], expectedQuery["institution_id"])
            XCTAssertEqual(query["min_amount"], expectedQuery["min_amount"])
            XCTAssertEqual(query["max_amount"], expectedQuery["max_amount"])
            let response = try self.makeHTTPResponse(for: request)
            return (response, Data("{\"total\":0,\"items\":[]}".utf8))
        }

        let client = makeClient()
        _ = try await client.fetchTransactions(
            TransactionFetchOptions(
                startDate: expectedQuery["start_date"] ?? "",
                endDate: expectedQuery["end_date"] ?? "",
                institutionId: expectedQuery["institution_id"] ?? "",
                minAmount: expectedQuery["min_amount"] ?? "",
                maxAmount: expectedQuery["max_amount"] ?? ""
            )
        )
    }

    func testDateOnlyMessageSearchSerializationMatchesContractCorpus() async throws {
        // #R065-T02
        let scenarios = try loadScenarios()
        let scenario = scenarios.classificationApi.messageSearch.dateOnlyEnd
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/matchy/messages/search")
            guard let requestURL = request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["end_date"], scenario.query["end_date"])
            XCTAssertEqual(query["limit"], scenario.query["limit"])
            XCTAssertNil(query["subject"])
            XCTAssertNil(query["query"])
            let response = try self.makeHTTPResponse(for: request)
            let body = "{\"query\":\"\(scenario.effective_query)\",\"items\":[]}"
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        let response = try await client.searchMessages(
            criteria: EmailSearchCriteria(receivedEndDate: scenario.query["end_date"] ?? ""),
            limit: Int(scenario.query["limit"] ?? "25") ?? 25
        )
        XCTAssertEqual(response.query, scenario.effective_query)
    }

    func testFixtureSearchQuerySummaryMatchesBackendContractCorpus() async throws {
        // #R065-T03
        let scenarios = try loadScenarios()
        let scenario = scenarios.classificationApi.messageSearch.dateOnlyStart
        let fixture = UITestingFixtureAPI()
        let response = try await fixture.searchMessages(
            criteria: EmailSearchCriteria(receivedStartDate: scenario.query["start_date"] ?? ""),
            limit: Int(scenario.query["limit"] ?? "25") ?? 25
        )
        XCTAssertEqual(response.query, scenario.effective_query)
    }
}
