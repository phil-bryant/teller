import Foundation

enum ConnectAction: String, CaseIterable, Codable, Sendable {
    case capture
    case reconnect
    case add

    var buttonLabel: String {
        switch self {
        case .capture:
            return "Connect"
        case .reconnect:
            return "Reconnect"
        case .add:
            return "Add Enrollment"
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

struct ConnectContextsResponse: Codable, Hashable, Sendable {
    let contexts: [ConnectContext]
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

struct ConnectDeleteContextRequest: Codable, Hashable, Sendable {
    let targetKey: String
}

struct ConnectDeleteContextResponse: Codable, Hashable, Sendable {
    let ok: Bool
    let moved_token: String?
    let moved_enrollment: String?
    let remaining: [ConnectContext]
}

struct ConnectStartSession: Hashable, Sendable, Identifiable {
    let id: UUID
    let action: ConnectAction
    let targetKey: String
    let applicationId: String
    let environment: String
    let enrollmentId: String

    init(
        id: UUID = UUID(),
        action: ConnectAction,
        targetKey: String,
        applicationId: String,
        environment: String,
        enrollmentId: String
    ) {
        self.id = id
        self.action = action
        self.targetKey = targetKey
        self.applicationId = applicationId
        self.environment = environment
        self.enrollmentId = enrollmentId
    }
}
