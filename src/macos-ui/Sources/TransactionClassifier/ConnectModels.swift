import Foundation

enum ConnectAction: String, CaseIterable, Codable, Sendable {
    case capture
    case reconnect
    case add

    var buttonLabel: String {
        switch self {
        case .capture:
            return "Add"
        case .reconnect:
            return "Edit"
        case .add:
            return "Add"
        }
    }
}

struct ConnectStatusResponse: Codable, Hashable, Sendable {
    let token_saved: Bool
    let saved_path: String
    let error: String
}

struct ConnectContext: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let source: String
    let institution_id: String
    let enrollment_id: String
    let token_path: String
    let enrollment_path: String

    var id: String { key }
    var hasEnrollmentId: Bool { !enrollment_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var displayInstitutionId: String { institution_id.isEmpty ? "unknown" : institution_id }
    var displayEnrollmentId: String { enrollment_id.isEmpty ? "<missing>" : enrollment_id }
}

struct ConnectStoreTokenRequest: Codable, Hashable, Sendable {
    let token: String
    let enrollmentId: String
    let action: String
    let targetKey: String
    let institutionIdHint: String
}

struct ConnectStoreTokenResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let path: String
    let enrollment_id_path: String
}

struct ConnectDeleteContextResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let moved_token: String?
    let moved_enrollment: String?
    let remaining: [ConnectContext]
}

/// Teller Connect SDK credentials carried with each `ConnectStartSession`.
/// Bundled together so callers pass one parameter instead of three, which keeps
/// `ConnectStartSession.init` under the strict parameter-count quality gate.
struct ConnectCredentials: Hashable, Sendable {
    let applicationId: String
    let environment: String
    let enrollmentId: String
}

struct ConnectStartSession: Hashable, Sendable, Identifiable {
    let id: UUID
    let action: ConnectAction
    let targetKey: String
    let credentials: ConnectCredentials

    var applicationId: String { credentials.applicationId }
    var environment: String { credentials.environment }
    var enrollmentId: String { credentials.enrollmentId }

    init(
        id: UUID = UUID(),
        action: ConnectAction,
        targetKey: String,
        credentials: ConnectCredentials
    ) {
        self.id = id
        self.action = action
        self.targetKey = targetKey
        self.credentials = credentials
    }
}
