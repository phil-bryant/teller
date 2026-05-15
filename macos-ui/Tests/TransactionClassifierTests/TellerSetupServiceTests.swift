import Foundation
import XCTest
@testable import TransactionClassifier

final class TellerSetupServiceTests: XCTestCase {
    private func makeTempHome() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("teller-setup-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: nil)
        return temp
    }

    private func fileMode(at path: String) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return String(format: "%03o", mode)
    }

    private func writeCurlStub(at path: URL, body: String) throws {
        try Data(body.utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: path.path)
    }

    func testLoadSnapshotReflectsTellerFilePresence() async throws {
        // #R001
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("app_123\n".utf8).write(to: tellerDir.appendingPathComponent("application_id.txt"))
        try Data("cert\n".utf8).write(to: tellerDir.appendingPathComponent("certificate.pem"))
        try Data("key\n".utf8).write(to: tellerDir.appendingPathComponent("private_key.pem"))

        let service = TellerSetupService(homeDirectory: home)
        let snapshot = try await service.loadSnapshot()
        XCTAssertTrue(snapshot.hasApplicationID)
        XCTAssertTrue(snapshot.hasCertificate)
        XCTAssertTrue(snapshot.hasPrivateKey)
        XCTAssertFalse(snapshot.hasAuthToken)
        XCTAssertTrue(snapshot.isReadyForInstitutionsSmoke)
    }

    func testSaveApplicationIDWritesSecureFileAndRejectsEmptyValue() async throws {
        // #R005 #R015
        let home = try makeTempHome()
        let service = TellerSetupService(homeDirectory: home)
        let savedPath = try await service.saveApplicationID(" app_native ")
        let savedValue = try String(contentsOf: URL(fileURLWithPath: savedPath), encoding: .utf8)
        XCTAssertEqual(savedValue, "app_native\n")
        XCTAssertEqual(try fileMode(at: home.appendingPathComponent(".teller").path), "700")
        XCTAssertEqual(try fileMode(at: savedPath), "400")

        do {
            _ = try await service.saveApplicationID("   ")
            XCTFail("Expected validation failure for empty app id")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Application ID is required"))
        }
    }

    func testSaveAuthTokenWritesJSONAndRejectsEmptyValue() async throws {
        // #R010 #R015
        let home = try makeTempHome()
        let service = TellerSetupService(homeDirectory: home)
        let savedPath = try await service.saveAuthToken("token_native")
        let payload = try Data(contentsOf: URL(fileURLWithPath: savedPath))
        let json = try JSONSerialization.jsonObject(with: payload) as? [String: String]
        XCTAssertEqual(json?["current"], "token_native")
        XCTAssertEqual(try fileMode(at: savedPath), "400")

        do {
            _ = try await service.saveAuthToken("\n")
            XCTFail("Expected validation failure for empty token")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Access token is required"))
        }
    }

    func testRunSmokeCheckSucceedsAndReturnsWarningWhenAccountsFail() async throws {
        // #R020 #R025
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("app_test\n".utf8).write(to: tellerDir.appendingPathComponent("application_id.txt"))
        try Data("CERT\n".utf8).write(to: tellerDir.appendingPathComponent("certificate.pem"))
        try Data("KEY\n".utf8).write(to: tellerDir.appendingPathComponent("private_key.pem"))
        try Data("{\"current\":\"token_test\"}\n".utf8).write(to: tellerDir.appendingPathComponent("auth_token.json"))

        let curlStub = home.appendingPathComponent("curl-stub.sh")
        try writeCurlStub(
            at: curlStub,
            body: """
            #!/usr/bin/env bash
            target=""
            for arg in "$@"; do
              target="$arg"
            done
            if [[ "$target" == *"/institutions" ]]; then
              printf '[]\\n200'
              exit 0
            fi
            if [[ "$target" == *"/accounts" ]]; then
              printf '{"error":"stale"}\\n401'
              exit 0
            fi
            printf '{"error":"unexpected"}\\n500'
            exit 0
            """
        )

        let service = TellerSetupService(homeDirectory: home, curlExecutable: curlStub.path)
        let result = try await service.runSmokeCheck()
        XCTAssertEqual(result.institutionsHTTPStatus, 200)
        XCTAssertEqual(result.institutionsCount, 0)
        XCTAssertEqual(result.accountsHTTPStatus, 401)
        XCTAssertTrue(result.warningText.contains("Accounts check returned HTTP 401"))
    }

    func testRunSmokeCheckWithoutTokenReturnsGuidanceWarning() async throws {
        // #R020 #R025
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("app_test\n".utf8).write(to: tellerDir.appendingPathComponent("application_id.txt"))
        try Data("CERT\n".utf8).write(to: tellerDir.appendingPathComponent("certificate.pem"))
        try Data("KEY\n".utf8).write(to: tellerDir.appendingPathComponent("private_key.pem"))

        let curlStub = home.appendingPathComponent("curl-stub.sh")
        try writeCurlStub(
            at: curlStub,
            body: """
            #!/usr/bin/env bash
            printf '[]\\n200'
            """
        )
        let service = TellerSetupService(homeDirectory: home, curlExecutable: curlStub.path)
        let result = try await service.runSmokeCheck()
        XCTAssertEqual(result.institutionsHTTPStatus, 200)
        XCTAssertNil(result.accountsHTTPStatus)
        XCTAssertTrue(result.warningText.contains("Auth token not found"))
    }

    func testRunSmokeCheckFailsWhenPrerequisitesMissing() async throws {
        // #R020
        let home = try makeTempHome()
        let service = TellerSetupService(homeDirectory: home)
        do {
            _ = try await service.runSmokeCheck()
            XCTFail("Expected validation failure for missing setup files")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Missing application id"))
        }
    }
}
