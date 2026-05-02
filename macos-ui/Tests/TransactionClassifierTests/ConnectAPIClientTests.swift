import Foundation
import XCTest
@testable import TransactionClassifier

final class ConnectAPIClientTests: XCTestCase {
    private func makeTempHome() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("connect-client-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: nil)
        return temp
    }

    private func makeClient(home: URL) -> ConnectAPIClient {
        ConnectAPIClient(homeDirectory: home)
    }

    func testFetchContextsReadsDefaultAndSuffixFiles() async throws {
        // #R001
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("{\"current\":\"token_default\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token.json"))
        try Data("enr_default\n".utf8).write(to: tellerDir.appendingPathComponent("enrollment_id.txt"))
        try Data("{\"current\":\"token_beta\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token_inst_beta.json"))
        try Data("enr_beta\n".utf8).write(to: tellerDir.appendingPathComponent("enrollment_id_inst_beta.txt"))

        let client = makeClient(home: home)
        let contexts = try await client.fetchContexts()
        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(contexts.first?.key, "default")
        XCTAssertTrue(contexts.contains { $0.key == "suffix:inst_beta" })
    }

    func testStoreTokenAddWritesSuffixedFiles() async throws {
        let home = try makeTempHome()
        let client = makeClient(home: home)
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
        XCTAssertTrue(response.path.hasSuffix("auth_token_inst_new.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: response.path))
        let saved = try Data(contentsOf: URL(fileURLWithPath: response.path))
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("token_abc"))
    }

    func testDeleteContextMovesFilesToTrashFolder() async throws {
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        let tokenPath = tellerDir.appendingPathComponent("auth_token_inst_beta.json")
        let enrollmentPath = tellerDir.appendingPathComponent("enrollment_id_inst_beta.txt")
        try Data("{\"current\":\"token_beta\"}\n".utf8).write(to: tokenPath)
        try Data("enr_beta\n".utf8).write(to: enrollmentPath)

        let client = makeClient(home: home)
        let response = try await client.deleteContext(targetKey: "suffix:inst_beta")
        XCTAssertTrue(response.ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: enrollmentPath.path))
        XCTAssertNotNil(response.moved_token)
        XCTAssertNotNil(response.moved_enrollment)
    }
}
