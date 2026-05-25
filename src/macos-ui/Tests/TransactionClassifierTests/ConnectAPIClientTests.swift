// Requirement test-case tags for requirements/macos-ui/ConnectAPIClient-requirements.md
// #R020-T02: Traceability anchor.

// Traceability numbered tags for requirements/macos-ui/ConnectAPIClient-requirements.md
// #R001-T01: Traceability anchor.
// #R005-T01: Traceability anchor.
// #R010-T01: Traceability anchor.
// #R010-T02: Traceability anchor.
// #R015-T01: Traceability anchor.
// #R020-T01: Traceability anchor.
// #R025-T01: Traceability anchor.
// #R030-T01: Traceability anchor.

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

    func testFetchStatusUsesSuffixTokenWhenDefaultMissing() async throws {
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("{\"current\":\"token_beta\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token_inst_beta.json"))
        try Data("enr_beta\n".utf8).write(to: tellerDir.appendingPathComponent("enrollment_id_inst_beta.txt"))

        let client = makeClient(home: home)
        let status = try await client.fetchStatus()
        XCTAssertTrue(status.token_saved)
        XCTAssertTrue(status.saved_path.hasSuffix("auth_token_inst_beta.json"))
    }

    func testFetchStatusReturnsFalseWhenNoValidTokenExists() async throws {
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("{\"current\":\"\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token.json"))

        let client = makeClient(home: home)
        let status = try await client.fetchStatus()
        XCTAssertFalse(status.token_saved)
        XCTAssertTrue(status.saved_path.hasSuffix("auth_token.json"))
    }

    func testFetchStatusSkipsMalformedTokenWhenValidSuffixExists() async throws {
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("{not-json}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token.json"))
        try Data("{\"current\":\"token_beta\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token_inst_beta.json"))
        try Data("enr_beta\n".utf8).write(to: tellerDir.appendingPathComponent("enrollment_id_inst_beta.txt"))

        let client = makeClient(home: home)
        let status = try await client.fetchStatus()
        XCTAssertTrue(status.token_saved)
        XCTAssertTrue(status.saved_path.hasSuffix("auth_token_inst_beta.json"))
    }

    func testStoreTokenAddWritesSuffixedFiles() async throws {
        let home = try makeTempHome()
        let client = makeClient(home: home)
        let first = try await client.storeToken(
            ConnectStoreTokenRequest(
                token: "token_abc",
                enrollmentId: "enr_new",
                action: "add",
                targetKey: "",
                institutionIdHint: "inst_new"
            )
        )
        let second = try await client.storeToken(
            ConnectStoreTokenRequest(
                token: "token_xyz",
                enrollmentId: "enr_newer",
                action: "add",
                targetKey: "",
                institutionIdHint: "inst_new"
            )
        )
        XCTAssertTrue(first.ok)
        XCTAssertTrue(second.ok)
        XCTAssertTrue(first.path.hasSuffix("auth_token_inst_new.json"))
        XCTAssertTrue(second.path.hasSuffix("auth_token_inst_new_1.json"))
        XCTAssertNotEqual(first.path, second.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        let saved = try Data(contentsOf: URL(fileURLWithPath: first.path))
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

    func testReconnectWithoutEnrollmentIDClearsStaleEnrollmentFile() async throws {
        // #R010
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("{\"current\":\"old_token\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token.json"))
        let enrollmentPath = tellerDir.appendingPathComponent("enrollment_id.txt")
        try Data("enr_disconnected\n".utf8).write(to: enrollmentPath)

        let client = makeClient(home: home)
        _ = try await client.storeToken(
            ConnectStoreTokenRequest(
                token: "new_token",
                enrollmentId: "",
                action: "reconnect",
                targetKey: "default",
                institutionIdHint: ""
            )
        )

        let savedEnrollment = try String(contentsOf: enrollmentPath, encoding: .utf8)
        XCTAssertEqual(savedEnrollment, "\n")
    }
}
