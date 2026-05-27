import Foundation

// #R001: Local Teller file inventory and readiness behavior.

struct TellerSetupSnapshot: Sendable {
    let hasApplicationID: Bool
    let hasCertificate: Bool
    let hasPrivateKey: Bool
    let hasAuthToken: Bool

    var isReadyForInstitutionsSmoke: Bool {
        hasApplicationID && hasCertificate && hasPrivateKey
    }
}

protocol TellerSetupAPI: Sendable {
    // #R005: In-app application-id provisioning is owned by the setup API surface used by the view model.
    // #R010: In-app auth-token provisioning is owned by the setup API surface used by the view model.
    // #R015: Setup file-permission enforcement is owned by the setup API surface used by the view model.
    // #R020: Smoke-check execution is owned by the setup API surface used by the view model.
    // #R025: Smoke-check warning semantics are owned by the setup API surface used by the view model.
    func loadSnapshot() async throws -> TellerSetupSnapshot
}

actor TellerSetupService: TellerSetupAPI {
    private let fileManager: FileManager
    private let homeDirectory: URL

    private var tellerDirectory: URL { homeDirectory.appendingPathComponent(".teller", isDirectory: true) }
    private var applicationIDFile: URL { tellerDirectory.appendingPathComponent("application_id.txt") }
    private var certificateFile: URL { tellerDirectory.appendingPathComponent("certificate.pem") }
    private var privateKeyFile: URL { tellerDirectory.appendingPathComponent("private_key.pem") }
    private var authTokenFile: URL { tellerDirectory.appendingPathComponent("auth_token.json") }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func loadSnapshot() async throws -> TellerSetupSnapshot {
        TellerSetupSnapshot(
            hasApplicationID: hasNonEmptyFile(applicationIDFile),
            hasCertificate: hasNonEmptyFile(certificateFile),
            hasPrivateKey: hasNonEmptyFile(privateKeyFile),
            hasAuthToken: hasNonEmptyFile(authTokenFile)
        )
    }

    private func hasNonEmptyFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }
}
