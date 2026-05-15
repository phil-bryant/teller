import Foundation

// #R001 #R005 #R010 #R015 #R020 #R025
// TellerSetupService requirement tags are mapped to behavior below:
// - #R001 local Teller file inventory/readiness,
// - #R005 secure application-id write path,
// - #R010 secure auth-token write path,
// - #R015 strict permission enforcement for setup files,
// - #R020 institutions/accounts smoke checks with mTLS,
// - #R025 smoke warnings and status formatting.

struct TellerSetupSnapshot: Sendable {
    let tellerDirectory: String
    let applicationIDPath: String
    let certificatePath: String
    let privateKeyPath: String
    let authTokenPath: String
    let hasApplicationID: Bool
    let hasCertificate: Bool
    let hasPrivateKey: Bool
    let hasAuthToken: Bool

    var isReadyForInstitutionsSmoke: Bool {
        hasApplicationID && hasCertificate && hasPrivateKey
    }
}

struct TellerSmokeCheckResult: Sendable {
    let institutionsHTTPStatus: Int
    let institutionsCount: Int?
    let accountsHTTPStatus: Int?
    let warningText: String
}

protocol TellerSetupAPI: Sendable {
    func loadSnapshot() throws -> TellerSetupSnapshot
    func saveApplicationID(_ applicationID: String) throws -> String
    func saveAuthToken(_ token: String) throws -> String
    func runSmokeCheck() throws -> TellerSmokeCheckResult
}

actor TellerSetupService: TellerSetupAPI {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let curlExecutable: String

    private var tellerDirectory: URL { homeDirectory.appendingPathComponent(".teller", isDirectory: true) }
    private var applicationIDFile: URL { tellerDirectory.appendingPathComponent("application_id.txt") }
    private var certificateFile: URL { tellerDirectory.appendingPathComponent("certificate.pem") }
    private var privateKeyFile: URL { tellerDirectory.appendingPathComponent("private_key.pem") }
    private var authTokenFile: URL { tellerDirectory.appendingPathComponent("auth_token.json") }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        curlExecutable: String = "/usr/bin/curl"
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.curlExecutable = curlExecutable
    }

    func loadSnapshot() throws -> TellerSetupSnapshot {
        let hasApplicationID = hasNonEmptyFile(applicationIDFile)
        let hasCertificate = hasNonEmptyFile(certificateFile)
        let hasPrivateKey = hasNonEmptyFile(privateKeyFile)
        let hasAuthToken = hasNonEmptyFile(authTokenFile)
        return TellerSetupSnapshot(
            tellerDirectory: tellerDirectory.path,
            applicationIDPath: applicationIDFile.path,
            certificatePath: certificateFile.path,
            privateKeyPath: privateKeyFile.path,
            authTokenPath: authTokenFile.path,
            hasApplicationID: hasApplicationID,
            hasCertificate: hasCertificate,
            hasPrivateKey: hasPrivateKey,
            hasAuthToken: hasAuthToken
        )
    }

    func saveApplicationID(_ applicationID: String) throws -> String {
        let normalized = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConnectServiceError.validation("Application ID is required.")
        }
        try writeText(normalized + "\n", to: applicationIDFile)
        return applicationIDFile.path
    }

    func saveAuthToken(_ token: String) throws -> String {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConnectServiceError.validation("Access token is required.")
        }
        let payload = ["current": normalized]
        var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        data.append(0x0A)
        try writeData(data, to: authTokenFile)
        return authTokenFile.path
    }

    func runSmokeCheck() throws -> TellerSmokeCheckResult {
        let snapshot = try loadSnapshot()
        guard snapshot.hasApplicationID else {
            throw ConnectServiceError.validation("Missing application id at \(snapshot.applicationIDPath).")
        }
        guard snapshot.hasCertificate else {
            throw ConnectServiceError.validation("Missing certificate at \(snapshot.certificatePath).")
        }
        guard snapshot.hasPrivateKey else {
            throw ConnectServiceError.validation("Missing private key at \(snapshot.privateKeyPath).")
        }

        let institutions = try runCurl(
            outputURL: "https://api.teller.io/institutions",
            token: nil
        )
        guard institutions.statusCode == 200 else {
            throw ConnectServiceError.validation(
                "Teller /institutions check failed with HTTP \(institutions.statusCode): \(institutions.bodyPreview)"
            )
        }

        let institutionsCount = parseJSONArrayCount(from: institutions.body)
        var accountsStatus: Int?
        var warningText = ""
        if snapshot.hasAuthToken {
            let token = try readAuthToken()
            let accounts = try runCurl(
                outputURL: "https://api.teller.io/accounts",
                token: token
            )
            accountsStatus = accounts.statusCode
            if accounts.statusCode != 200 {
                warningText = "Accounts check returned HTTP \(accounts.statusCode). Reconnect in Connect tab if token is stale."
            }
        } else {
            warningText = "Auth token not found. Run Connect to capture an access token for accounts smoke checks."
        }

        return TellerSmokeCheckResult(
            institutionsHTTPStatus: institutions.statusCode,
            institutionsCount: institutionsCount,
            accountsHTTPStatus: accountsStatus,
            warningText: warningText
        )
    }

    private func hasNonEmptyFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    private func readAuthToken() throws -> String {
        let data = try Data(contentsOf: authTokenFile)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConnectServiceError.validation("Invalid token payload at \(authTokenFile.path).")
        }
        let token = (payload["current"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw ConnectServiceError.validation("Token payload at \(authTokenFile.path) has no .current value.")
        }
        return token
    }

    private func parseJSONArrayCount(from body: Data) -> Int? {
        guard let rows = try? JSONSerialization.jsonObject(with: body) as? [Any] else {
            return nil
        }
        return rows.count
    }

    private func runCurl(outputURL: String, token: String?) throws -> (statusCode: Int, body: Data, bodyPreview: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: curlExecutable)
        var args = [
            "-sS",
            "--max-time", "8",
            "-w", "\n%{http_code}",
            "--cert", certificateFile.path,
            "--key", privateKeyFile.path,
        ]
        if let token {
            args += ["-u", "\(token):"]
        }
        args.append(outputURL)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ConnectServiceError.validation("Failed to execute curl for \(outputURL): \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ConnectServiceError.validation("curl failed for \(outputURL): \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard let newlineIndex = text.lastIndex(of: "\n") else {
            throw ConnectServiceError.validation("Unexpected curl output for \(outputURL).")
        }
        let bodyString = String(text[..<newlineIndex])
        let statusString = String(text[text.index(after: newlineIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let statusCode = Int(statusString) else {
            throw ConnectServiceError.validation("Invalid HTTP status from curl for \(outputURL).")
        }
        let bodyData = Data(bodyString.utf8)
        let preview = bodyString.replacingOccurrences(of: "\n", with: " ")
        return (statusCode, bodyData, String(preview.prefix(160)))
    }

    private func ensureTellerDirectory() throws {
        try fileManager.createDirectory(at: tellerDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: tellerDirectory.path)
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
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o400)], ofItemAtPath: destination.path)
    }
}
