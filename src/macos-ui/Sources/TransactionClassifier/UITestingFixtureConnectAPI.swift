import Foundation

// #R015: Simulate connect-context lifecycle actions for deterministic UI test flows.

actor UITestingFixtureConnectAPI: ConnectAPI {
    private var contexts: [ConnectContext] = [
        ConnectContext(
            key: "default",
            source: "default",
            institution_id: "inst_alpha",
            enrollment_id: "enr_alpha",
            token_path: "/Users/test/.teller/auth_token.json",
            enrollment_path: "/Users/test/.teller/enrollment_id.txt"
        ),
        ConnectContext(
            key: "suffix:inst_beta",
            source: "suffix",
            institution_id: "inst_beta",
            enrollment_id: "enr_beta",
            token_path: "/Users/test/.teller/auth_token_inst_beta.json",
            enrollment_path: "/Users/test/.teller/enrollment_id_inst_beta.txt"
        ),
    ]

    func fetchStatus() async throws -> ConnectStatusResponse {
        ConnectStatusResponse(token_saved: true, saved_path: contexts.first?.token_path ?? "", error: "")
    }

    func fetchContexts() async throws -> [ConnectContext] {
        contexts
    }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        let institution = request.institutionIdHint.isEmpty ? "manual" : request.institutionIdHint
        switch request.action {
        case ConnectAction.reconnect.rawValue:
            if let index = contexts.firstIndex(where: { $0.key == request.targetKey }) {
                let row = contexts[index]
                contexts[index] = ConnectContext(
                    key: row.key,
                    source: row.source,
                    institution_id: row.institution_id,
                    enrollment_id: request.enrollmentId.isEmpty ? row.enrollment_id : request.enrollmentId,
                    token_path: row.token_path,
                    enrollment_path: row.enrollment_path
                )
            }
        case ConnectAction.add.rawValue:
            let key = "suffix:\(institution)"
            contexts.append(
                ConnectContext(
                    key: key,
                    source: "suffix",
                    institution_id: institution,
                    enrollment_id: request.enrollmentId,
                    token_path: "/Users/test/.teller/auth_token_\(institution).json",
                    enrollment_path: "/Users/test/.teller/enrollment_id_\(institution).txt"
                )
            )
        default:
            break
        }
        return ConnectStoreTokenResponse(ok: true, path: contexts.first?.token_path ?? "", enrollment_id_path: contexts.first?.enrollment_path ?? "")
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        contexts.removeAll { $0.key == targetKey }
        return ConnectDeleteContextResponse(ok: true, moved_token: nil, moved_enrollment: nil, remaining: contexts)
    }

    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession {
        if action == .reconnect {
            guard let selectedContext, selectedContext.hasEnrollmentId else {
                throw ConnectServiceError.validation("Selected context has no enrollment_id.")
            }
            return ConnectStartSession(
                action: action,
                targetKey: selectedContext.key,
                credentials: ConnectCredentials(
                    applicationId: "app_fixture",
                    environment: "development",
                    enrollmentId: selectedContext.enrollment_id
                )
            )
        }
        return ConnectStartSession(
            action: action,
            targetKey: "",
            credentials: ConnectCredentials(
                applicationId: "app_fixture",
                environment: "development",
                enrollmentId: ""
            )
        )
    }
}
