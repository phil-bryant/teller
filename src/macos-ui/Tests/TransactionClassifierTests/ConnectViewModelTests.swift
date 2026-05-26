import Foundation
import XCTest
@testable import TransactionClassifier

actor MockConnectAPI: ConnectAPI {
    var status: ConnectStatusResponse
    var contexts: [ConnectContext]
    var lastStored: ConnectStoreTokenRequest?
    var lastDeleteTarget: String?

    init(status: ConnectStatusResponse, contexts: [ConnectContext]) {
        self.status = status
        self.contexts = contexts
    }

    func fetchStatus() async throws -> ConnectStatusResponse {
        status
    }

    func fetchContexts() async throws -> [ConnectContext] {
        contexts
    }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        lastStored = request
        if request.action == ConnectAction.add.rawValue {
            contexts.append(
                ConnectContext(
                    key: "suffix:\(request.institutionIdHint)",
                    source: "suffix",
                    institution_id: request.institutionIdHint,
                    enrollment_id: request.enrollmentId,
                    token_path: "/tmp/auth_token_\(request.institutionIdHint).json",
                    enrollment_path: "/tmp/enrollment_id_\(request.institutionIdHint).txt"
                )
            )
        }
        return ConnectStoreTokenResponse(ok: true, path: "/tmp/auth_token.json", enrollment_id_path: "/tmp/enrollment_id.txt")
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        lastDeleteTarget = targetKey
        contexts.removeAll { $0.key == targetKey }
        return ConnectDeleteContextResponse(ok: true, moved_token: nil, moved_enrollment: nil, remaining: contexts)
    }

    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession {
        if action == .reconnect {
            guard let selectedContext, selectedContext.hasEnrollmentId else {
                throw ConnectServiceError.validation("The selected connection cannot be edited.")
            }
            return ConnectStartSession(
                action: action,
                targetKey: selectedContext.key,
                applicationId: "app_test",
                environment: "development",
                enrollmentId: selectedContext.enrollment_id
            )
        }
        return ConnectStartSession(
            action: action,
            targetKey: "",
            applicationId: "app_test",
            environment: "development",
            enrollmentId: ""
        )
    }

    func recordedLastStored() -> ConnectStoreTokenRequest? {
        lastStored
    }

    func recordedLastDeleteTarget() -> String? {
        lastDeleteTarget
    }
}

private func sampleContext(
    key: String = "default",
    institution: String = "inst_alpha",
    enrollment: String = "enr_alpha"
) -> ConnectContext {
    ConnectContext(
        key: key,
        source: "default",
        institution_id: institution,
        enrollment_id: enrollment,
        token_path: "/tmp/auth_token.json",
        enrollment_path: "/tmp/enrollment_id.txt"
    )
}

final class ConnectViewModelTests: XCTestCase {
    @MainActor
    func testLoadAllPopulatesContextsAndStatus() async {
        // #R001-T02 #R025-T01
        let api = MockConnectAPI(
            status: ConnectStatusResponse(token_saved: true, saved_path: "/tmp/auth_token.json", error: ""),
            contexts: [sampleContext()]
        )
        let vm = ConnectViewModel(api: api)
        await vm.loadAll()
        XCTAssertEqual(vm.contexts.count, 1)
        XCTAssertEqual(vm.selectedContextKey, "default")
        XCTAssertEqual(vm.statusText, "Connections ready.")
    }

    @MainActor
    func testEditStartsSessionForSelectedConnection() async {
        // #R005-T01 #R020-T02
        let api = MockConnectAPI(
            status: ConnectStatusResponse(token_saved: false, saved_path: "", error: ""),
            contexts: [sampleContext(key: "suffix:inst_beta", institution: "inst_beta", enrollment: "enr_beta")]
        )
        let vm = ConnectViewModel(api: api)
        await vm.loadAll()
        vm.selectedContextKey = "suffix:inst_beta"
        await vm.startConnect(action: .reconnect)
        XCTAssertEqual(vm.activeSession?.action, .reconnect)
        XCTAssertEqual(vm.activeSession?.targetKey, "suffix:inst_beta")
    }

    @MainActor
    func testAddStartsAddSession() async {
        // #R005-T02 #R020-T02
        let api = MockConnectAPI(
            status: ConnectStatusResponse(token_saved: false, saved_path: "", error: ""),
            contexts: [sampleContext()]
        )
        let vm = ConnectViewModel(api: api)
        await vm.loadAll()
        await vm.startConnect(action: .add)
        XCTAssertEqual(vm.activeSession?.action, .add)
        XCTAssertEqual(vm.activeSession?.targetKey, "")
    }

    @MainActor
    func testDeleteSelectedRemovesContext() async {
        // #R010-T01
        let api = MockConnectAPI(
            status: ConnectStatusResponse(token_saved: false, saved_path: "", error: ""),
            contexts: [sampleContext(key: "default"), sampleContext(key: "suffix:inst_beta", institution: "inst_beta", enrollment: "enr_beta")]
        )
        let vm = ConnectViewModel(api: api)
        await vm.loadAll()
        vm.selectedContextKey = "suffix:inst_beta"
        await vm.deleteSelectedContext()
        XCTAssertEqual(vm.contexts.count, 1)
        let deleteTarget = await api.recordedLastDeleteTarget()
        XCTAssertEqual(deleteTarget, "suffix:inst_beta")
    }

    @MainActor
    func testEditWithoutSelectionSurfacesValidationError() async {
        // #R020-T01
        let api = MockConnectAPI(
            status: ConnectStatusResponse(token_saved: false, saved_path: "", error: ""),
            contexts: [sampleContext(key: "suffix:inst_beta", institution: "inst_beta", enrollment: "")]
        )
        let vm = ConnectViewModel(api: api)
        await vm.loadAll()
        vm.selectedContextKey = "suffix:inst_beta"
        await vm.startConnect(action: .reconnect)
        XCTAssertFalse(vm.errorText.isEmpty)
        XCTAssertNil(vm.activeSession)
    }

    @MainActor
    func testLoadAllServiceFailureSurfacesConnectionsError() async {
        // #R025-T02
        struct FailingConnectAPI: ConnectAPI {
            func fetchStatus() async throws -> ConnectStatusResponse {
                ConnectStatusResponse(token_saved: false, saved_path: "", error: "disk read failed")
            }

            func fetchContexts() async throws -> [ConnectContext] {
                throw ConnectServiceError.validation("could not load connections")
            }

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

        let vm = ConnectViewModel(api: FailingConnectAPI())
        await vm.loadAll()
        XCTAssertTrue(vm.statusText.localizedCaseInsensitiveContains("could not load connections"))
        XCTAssertFalse(vm.errorText.isEmpty)
    }

    @MainActor
    func testSetupSnapshotUpdatesConnectViewModelState() async {
        // #R001-T02
        struct SetupMockAPI: TellerSetupAPI {
            let snapshot: TellerSetupSnapshot

            func loadSnapshot() async throws -> TellerSetupSnapshot { snapshot }
            func saveApplicationID(_ applicationID: String) async throws -> String { _ = applicationID; return "/tmp/application_id.txt" }
            func saveAuthToken(_ token: String) async throws -> String { _ = token; return "/tmp/auth_token.json" }
            func runSmokeCheck() async throws -> TellerSmokeCheckResult {
                TellerSmokeCheckResult(institutionsHTTPStatus: 200, institutionsCount: 1, accountsHTTPStatus: nil, warningText: "")
            }
        }

        let snapshot = TellerSetupSnapshot(
            tellerDirectory: "/tmp/.teller",
            applicationIDPath: "/tmp/.teller/application_id.txt",
            certificatePath: "/tmp/.teller/certificate.pem",
            privateKeyPath: "/tmp/.teller/private_key.pem",
            authTokenPath: "/tmp/.teller/auth_token.json",
            hasApplicationID: true,
            hasCertificate: true,
            hasPrivateKey: false,
            hasAuthToken: false
        )
        let vm = ConnectViewModel(
            api: MockConnectAPI(
                status: ConnectStatusResponse(token_saved: false, saved_path: "", error: ""),
                contexts: []
            ),
            setupAPI: SetupMockAPI(snapshot: snapshot)
        )
        await vm.loadAll()
        XCTAssertEqual(vm.setupSnapshot?.hasApplicationID, true)
        XCTAssertEqual(vm.setupSnapshot?.hasPrivateKey, false)
        XCTAssertTrue(vm.setupStatusText.contains("Step 18 setup is"))
    }
}
