import Foundation

// #R001: Context discovery and status reporting behavior.
// #R005: Add-flow suffixing and local path generation behavior.
// #R010: Reconnect targeting behavior for existing contexts.
// #R015: Trash-based deletion behavior for enrollment artifacts.
// #R020: Start-session validation behavior.
// #R025: Permission checks and secure-write behavior.
// #R030: Best-effort institution inference behavior.

protocol ConnectAPI: Sendable {
    func fetchStatus() async throws -> ConnectStatusResponse
    func fetchContexts() async throws -> [ConnectContext]
    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse
    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse
    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession
}

actor ConnectAPIClient: ConnectAPI {
    private let fileManager: FileManager
    private let environment: [String: String]
    private var lastError = ""
    private let homeDirectory: URL

    private var tellerDirectory: URL { homeDirectory.appendingPathComponent(".teller", isDirectory: true) }
    private var appIDFile: URL { tellerDirectory.appendingPathComponent("application_id.txt") }
    private var authTokenFile: URL { tellerDirectory.appendingPathComponent("auth_token.json") }
    private var enrollmentIDFile: URL { tellerDirectory.appendingPathComponent("enrollment_id.txt") }
    private var certFile: URL { tellerDirectory.appendingPathComponent("certificate.pem") }
    private var keyFile: URL { tellerDirectory.appendingPathComponent("private_key.pem") }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.environment = environment
    }

    func fetchStatus() async throws -> ConnectStatusResponse {
        do {
            let contexts = try discoverLocalContexts()
            var firstError: String?
            for context in contexts {
                let token: String
                do {
                    token = try tokenFromFile(path: URL(fileURLWithPath: context.token_path))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                    continue
                }
                if !token.isEmpty {
                    return ConnectStatusResponse(
                        token_saved: true,
                        saved_path: context.token_path,
                        error: lastError
                    )
                }
            }
            if let firstError {
                lastError = firstError
            }
            return ConnectStatusResponse(
                token_saved: false,
                saved_path: authTokenFile.path,
                error: lastError
            )
        } catch {
            lastError = error.localizedDescription
            return ConnectStatusResponse(
                token_saved: false,
                saved_path: authTokenFile.path,
                error: lastError
            )
        }
    }

    func fetchContexts() async throws -> [ConnectContext] {
        try discoverLocalContexts()
    }

    func storeToken(_ request: ConnectStoreTokenRequest) async throws -> ConnectStoreTokenResponse {
        do {
            let token = request.token.trimmingCharacters(in: .whitespacesAndNewlines)
            let enrollmentID = request.enrollmentId.trimmingCharacters(in: .whitespacesAndNewlines)
            let institutionHint = request.institutionIdHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let inferredDetails = inferIdentityDetails(token: token)
            let resolvedEnrollmentID = enrollmentID.isEmpty ? inferredDetails.enrollmentID : enrollmentID

            guard !token.isEmpty else {
                throw ConnectServiceError.validation("Token is required.")
            }

            var outputTokenFile = authTokenFile
            var outputEnrollmentFile = enrollmentIDFile
            let contexts = try discoverLocalContexts()

            if request.action == ConnectAction.reconnect.rawValue {
                guard let target = contexts.first(where: { $0.key == request.targetKey }) else {
                    throw ConnectServiceError.notFound("Connection not found for editing.")
                }
                outputTokenFile = URL(fileURLWithPath: target.token_path)
                outputEnrollmentFile = URL(fileURLWithPath: target.enrollment_path)
            } else if request.action == ConnectAction.add.rawValue {
                let inferredInstitution = inferredDetails.institutionID
                let baseSuffix = sanitizeSuffix(
                    institutionHint.isEmpty
                        ? (resolvedEnrollmentID.isEmpty ? inferredInstitution : resolvedEnrollmentID)
                        : institutionHint
                )
                let suffix = ensureUniqueSuffix(base: baseSuffix)
                outputTokenFile = tellerDirectory.appendingPathComponent("auth_token_\(suffix).json")
                outputEnrollmentFile = tellerDirectory.appendingPathComponent("enrollment_id_\(suffix).txt")
            }

            try ensureTellerDirectory()
            try writeTokenJSON(token: token, to: outputTokenFile)
            try writeText(resolvedEnrollmentID + "\n", to: outputEnrollmentFile)
            lastError = ""
            return ConnectStoreTokenResponse(
                ok: true,
                path: outputTokenFile.path,
                enrollment_id_path: outputEnrollmentFile.path
            )
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func deleteContext(targetKey: String) async throws -> ConnectDeleteContextResponse {
        do {
            let contexts = try discoverLocalContexts()
            guard let target = contexts.first(where: { $0.key == targetKey }) else {
                throw ConnectServiceError.notFound("Context not found.")
            }
            let movedToken = try moveToTrash(URL(fileURLWithPath: target.token_path))
            let movedEnrollment = try moveToTrash(URL(fileURLWithPath: target.enrollment_path))
            let remaining = try discoverLocalContexts()
            lastError = ""
            return ConnectDeleteContextResponse(
                ok: true,
                moved_token: movedToken,
                moved_enrollment: movedEnrollment,
                remaining: remaining
            )
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func startSession(action: ConnectAction, selectedContext: ConnectContext?) async throws -> ConnectStartSession {
        let applicationID = (try? String(contentsOf: appIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        guard !applicationID.isEmpty else {
            throw ConnectServiceError.validation("Missing application id at \(appIDFile.path).")
        }

        if action == .reconnect {
            guard let selectedContext else {
                throw ConnectServiceError.validation("Select a connection before editing.")
            }
            guard selectedContext.hasEnrollmentId else {
                throw ConnectServiceError.validation("The selected connection cannot be edited.")
            }
            return ConnectStartSession(
                action: action,
                targetKey: selectedContext.key,
                applicationId: applicationID,
                environment: environment["CONNECT_ENVIRONMENT"] ?? "development",
                enrollmentId: selectedContext.enrollment_id
            )
        }

        return ConnectStartSession(
            action: action,
            targetKey: "",
            applicationId: applicationID,
            environment: environment["CONNECT_ENVIRONMENT"] ?? "development",
            enrollmentId: ""
        )
    }

    private func discoverLocalContexts() throws -> [ConnectContext] {
        var contexts: [ConnectContext] = []
        let metadataMap = try loadMetadataInstitutionMap()

        if fileManager.fileExists(atPath: authTokenFile.path) || fileManager.fileExists(atPath: enrollmentIDFile.path) {
            let enrollmentID = (try? readTextIfExists(path: enrollmentIDFile)) ?? ""
            let token = (try? tokenFromFile(path: authTokenFile)) ?? ""
            let inferred = inferInstitutionID(token: token)
            contexts.append(
                ConnectContext(
                    key: "default",
                    source: "default",
                    institution_id: inferred.isEmpty ? (metadataMap[enrollmentID] ?? "") : inferred,
                    enrollment_id: enrollmentID,
                    token_path: authTokenFile.path,
                    enrollment_path: enrollmentIDFile.path
                )
            )
        }

        guard fileManager.fileExists(atPath: tellerDirectory.path) else {
            return contexts
        }

        let tokenFiles = try fileManager.contentsOfDirectory(at: tellerDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("auth_token_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for tokenFile in tokenFiles {
            let filename = tokenFile.lastPathComponent
            let suffix = String(filename.dropFirst("auth_token_".count).dropLast(".json".count))
            let enrollmentFile = tellerDirectory.appendingPathComponent("enrollment_id_\(suffix).txt")
            let enrollmentID = (try? readTextIfExists(path: enrollmentFile)) ?? ""
            let token = (try? tokenFromFile(path: tokenFile)) ?? ""
            let inferred = inferInstitutionID(token: token)
            contexts.append(
                ConnectContext(
                    key: "suffix:\(suffix)",
                    source: "suffix",
                    institution_id: inferred.isEmpty ? (metadataMap[enrollmentID] ?? suffix) : inferred,
                    enrollment_id: enrollmentID,
                    token_path: tokenFile.path,
                    enrollment_path: enrollmentFile.path
                )
            )
        }

        return contexts
    }

    private func loadMetadataInstitutionMap() throws -> [String: String] {
        let metadataFile = tellerDirectory.appendingPathComponent("enrollments.json")
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            return [:]
        }
        let data = try Data(contentsOf: metadataFile)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var mapped: [String: String] = [:]
        for row in rows {
            guard let enrollmentID = row["enrollment_id"] as? String, !enrollmentID.isEmpty else { continue }
            guard let institutionID = row["institution_id"] as? String, !institutionID.isEmpty else { continue }
            mapped[enrollmentID] = institutionID
        }
        return mapped
    }

    private func tokenFromFile(path: URL) throws -> String {
        guard fileManager.fileExists(atPath: path.path) else {
            return ""
        }
        let data = try Data(contentsOf: path)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return payload?["current"] as? String ?? ""
    }

    private func readTextIfExists(path: URL) throws -> String {
        guard fileManager.fileExists(atPath: path.path) else {
            return ""
        }
        return try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferInstitutionID(token: String) -> String {
        inferIdentityDetails(token: token).institutionID
    }

    private func inferIdentityDetails(token: String) -> (institutionID: String, enrollmentID: String) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else { return ("", "") }
        guard fileManager.fileExists(atPath: certFile.path), fileManager.fileExists(atPath: keyFile.path) else {
            return ("", "")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-sS",
            "--max-time", "8",
            "--cert", certFile.path,
            "--key", keyFile.path,
            "-u", "\(normalizedToken):",
            "https://api.teller.io/identity",
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return ("", "")
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = rows.first,
                  let account = first["account"] as? [String: Any],
                  let institution = account["institution"] as? [String: Any] else {
                return ("", "")
            }
            let institutionID = institution["id"] as? String ?? ""
            let enrollmentID = account["enrollment_id"] as? String ?? ""
            return (institutionID, enrollmentID)
        } catch {
            return ("", "")
        }
    }

    private func sanitizeSuffix(_ value: String) -> String {
        let lowercased = value.lowercased()
        let mapped = lowercased.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        let trimmed = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "enrollment" : trimmed
    }

    private func ensureUniqueSuffix(base: String) -> String {
        var candidate = base
        var counter = 1
        while fileManager.fileExists(atPath: tellerDirectory.appendingPathComponent("auth_token_\(candidate).json").path)
            || fileManager.fileExists(atPath: tellerDirectory.appendingPathComponent("enrollment_id_\(candidate).txt").path) {
            candidate = "\(base)_\(counter)"
            counter += 1
        }
        return candidate
    }

    private func ensureTellerDirectory() throws {
        try fileManager.createDirectory(at: tellerDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: tellerDirectory.path)
    }

    private func writeTokenJSON(token: String, to destination: URL) throws {
        let payload = ["current": token]
        var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        data.append(0x0A)
        try writeData(data, to: destination)
    }

    private func writeText(_ text: String, to destination: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw ConnectServiceError.validation("Unable to encode text as UTF-8.")
        }
        try writeData(data, to: destination)
    }

    private func writeData(_ data: Data, to destination: URL) throws {
        try ensureTellerDirectory()
        let tempURL = tellerDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o400)], ofItemAtPath: tempURL.path)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: tempURL, to: destination)
        } else {
            try fileManager.moveItem(at: tempURL, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o400)], ofItemAtPath: destination.path)
    }

    private func moveToTrash(_ path: URL) throws -> String? {
        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }
        let trashRoot = homeDirectory
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent("teller-enrollment-removals", isDirectory: true)
        try fileManager.createDirectory(at: trashRoot, withIntermediateDirectories: true, attributes: nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let destination = trashRoot.appendingPathComponent("\(path.lastPathComponent).\(formatter.string(from: Date()))")
        try fileManager.moveItem(at: path, to: destination)
        return destination.path
    }
}

enum ConnectServiceError: LocalizedError {
    case validation(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .notFound(let message):
            return message
        }
    }
}
