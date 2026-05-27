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

    func testLoadSnapshotReflectsTellerFilePresence() async throws {
        // #R001-T01
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

    func testLoadSnapshotTreatsEmptyAuthTokenAsMissing() async throws {
        // #R010-T02
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data().write(to: tellerDir.appendingPathComponent("auth_token.json"))

        let service = TellerSetupService(homeDirectory: home)
        let snapshot = try await service.loadSnapshot()
        XCTAssertFalse(snapshot.hasAuthToken)
    }

    @MainActor
    func testConnectViewModelReflectsSetupSnapshotReadiness() async throws {
        // #R001-T02
        let home = try makeTempHome()
        let tellerDir = home.appendingPathComponent(".teller", isDirectory: true)
        try FileManager.default.createDirectory(at: tellerDir, withIntermediateDirectories: true, attributes: nil)
        try Data("app_123\n".utf8).write(to: tellerDir.appendingPathComponent("application_id.txt"))

        let setupService = TellerSetupService(homeDirectory: home)
        let vm = ConnectViewModel(
            api: TellerSetupConnectAPIStub(),
            setupAPI: setupService
        )
        await vm.loadAll()
        XCTAssertEqual(vm.setupSnapshot?.hasApplicationID, true)
        XCTAssertTrue(vm.setupStatusText.contains("Step 18 setup is"))
    }
}

private actor TellerSetupConnectAPIStub: ConnectAPI {
    func fetchStatus() async throws -> ConnectStatusResponse {
        ConnectStatusResponse(token_saved: false, saved_path: "", error: "")
    }

    func fetchContexts() async throws -> [ConnectContext] { [] }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        _ = request
        throw ConnectServiceError.validation("unused")
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        _ = targetKey
        throw ConnectServiceError.validation("unused")
    }

    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession {
        _ = action; _ = selectedContext
        throw ConnectServiceError.validation("unused")
    }
}
