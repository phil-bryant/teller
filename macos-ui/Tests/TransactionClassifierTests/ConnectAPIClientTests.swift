import Foundation
import XCTest
@testable import TransactionClassifier

final class ConnectAPIClientTests: XCTestCase {
    private func makeClient(baseURL: URL = URL(string: "http://127.0.0.1:8080")!) -> ConnectAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        return ConnectAPIClient(baseURL: baseURL, session: session)
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

    func testFetchContextsUsesConnectEndpoint() async throws {
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/contexts")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"contexts":[{"key":"default","source":"default","institution_id":"inst_alpha","enrollment_id":"enr_alpha","token_path":"/tmp/a.json","enrollment_path":"/tmp/a.txt"}]}
            """
            return (response, Data(body.utf8))
        }

        let client = makeClient()
        let contexts = try await client.fetchContexts()
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.key, "default")
    }

    func testStoreTokenPostsExpectedPayload() async throws {
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/store-token")
            let body = try self.requestBodyData(request)
            let payload = try JSONDecoder().decode(ConnectStoreTokenRequest.self, from: body)
            XCTAssertEqual(payload.action, "add")
            XCTAssertEqual(payload.targetKey, "")
            XCTAssertEqual(payload.institutionIdHint, "inst_new")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let responseBody = """
            {"ok":true,"path":"/tmp/auth_token_inst_new.json","enrollment_id_path":"/tmp/enrollment_id_inst_new.txt"}
            """
            return (response, Data(responseBody.utf8))
        }

        let client = makeClient()
        let response = try await client.storeToken(
            ConnectStoreTokenRequest(
                token: "token_abc",
                enrollmentId: "enr_new",
                action: "add",
                targetKey: "",
                institutionIdHint: "inst_new"
            )
        )
        XCTAssertTrue(response.ok)
    }

    func testDeleteContextPostsTargetKey() async throws {
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/delete-context")
            let body = try self.requestBodyData(request)
            let payload = try JSONDecoder().decode(ConnectDeleteContextRequest.self, from: body)
            XCTAssertEqual(payload.targetKey, "suffix:inst_beta")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let responseBody = """
            {"ok":true,"moved_token":"/Trash/token.json","moved_enrollment":"/Trash/enrollment.txt","remaining":[]}
            """
            return (response, Data(responseBody.utf8))
        }

        let client = makeClient()
        let response = try await client.deleteContext(targetKey: "suffix:inst_beta")
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.remaining.count, 0)
    }
}
