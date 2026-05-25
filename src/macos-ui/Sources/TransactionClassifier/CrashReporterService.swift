import Foundation
import CrashReporter
import Darwin

enum CrashReporterService {
    private static let storageDirectoryName = "CrashReports"
    private static let sessionMarkerFileName = "session-active.json"

    static func start() {
        guard let crashReporter = makeCrashReporter() else {
            log("CrashReporter: failed to create PLCrashReporter instance")
            return
        }

        persistPendingCrashReportIfPresent(crashReporter)
        persistUncleanTerminationIfPresent()

        do {
            try crashReporter.enableAndReturnError()
        } catch {
            log("CrashReporter: failed to enable reporter: \(error)")
        }

        markSessionActive()

        // Deliberate crash toggle for local validation of collection flow.
        if ProcessInfo.processInfo.environment["TELLER_MACOS_FORCE_CRASH_ON_LAUNCH"] == "1" {
            // Deliberate fatal crash for launch-replay validation.
            fatalError("Intentional crash for PLCrashReporter verification")
        }
    }

    static func markGracefulShutdown() {
        do {
            let markerURL = try sessionMarkerURL()
            if FileManager.default.fileExists(atPath: markerURL.path) {
                try FileManager.default.removeItem(at: markerURL)
            }
        } catch {
            log("CrashReporter: failed to clear session marker: \(error)")
        }
    }

    private static func makeCrashReporter() -> PLCrashReporter? {
        #if DEBUG
            let symbolicationStrategy: PLCrashReporterSymbolicationStrategy = .all
        #else
            let symbolicationStrategy: PLCrashReporterSymbolicationStrategy = []
        #endif

        let config = PLCrashReporterConfig(
            signalHandlerType: .mach,
            symbolicationStrategy: symbolicationStrategy
        )
        return PLCrashReporter(configuration: config)
    }

    private static func persistPendingCrashReportIfPresent(_ crashReporter: PLCrashReporter) {
        guard crashReporter.hasPendingCrashReport() else {
            return
        }

        do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
            let fileURL = try writeCrashReport(data)
            log("CrashReporter: saved pending crash report to \(fileURL.path)")
            crashReporter.purgePendingCrashReport()
        } catch {
            log("CrashReporter: failed handling pending report: \(error)")
        }
    }

    private static func markSessionActive() {
        do {
            let markerURL = try sessionMarkerURL()
            let marker = [
                "pid": Int(getpid()),
                "started_at": ISO8601DateFormatter().string(from: Date()),
                "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            ] as [String: Any]
            let markerData = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
            try markerData.write(to: markerURL, options: .atomic)
        } catch {
            log("CrashReporter: failed to write session marker: \(error)")
        }
    }

    private static func persistUncleanTerminationIfPresent() {
        do {
            let markerURL = try sessionMarkerURL()
            guard FileManager.default.fileExists(atPath: markerURL.path) else {
                return
            }

            let markerData = try Data(contentsOf: markerURL)
            let markerJSON = (try JSONSerialization.jsonObject(with: markerData)) as? [String: Any]

            let outputDirectory = try crashReportDirectory()
            let basename = "unclean-exit-\(timestamp())"
            let outputURL = outputDirectory.appendingPathComponent("\(basename).json")

            var payload: [String: Any] = [
                "format": "unclean_exit",
                "captured_at": ISO8601DateFormatter().string(from: Date()),
                "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "message": "Detected previous app session without graceful shutdown; likely force quit, hang kill, or OS/process termination.",
            ]
            if let markerJSON {
                payload["previous_session"] = markerJSON
            }

            let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try payloadData.write(to: outputURL, options: .atomic)
            try FileManager.default.removeItem(at: markerURL)
            log("CrashReporter: saved unclean termination marker to \(outputURL.path)")
        } catch {
            log("CrashReporter: failed handling unclean termination marker: \(error)")
        }
    }

    private static func log(_ message: String) {
        fputs("\(message)\n", stderr)
        fflush(stderr)
    }

    private static func writeCrashReport(_ data: Data) throws -> URL {
        let outputDirectory = try crashReportDirectory()
        let basename = "crash-\(timestamp())"

        let crashFileURL = outputDirectory.appendingPathComponent("\(basename).plcrash")
        try data.write(to: crashFileURL, options: .atomic)

        let metadataURL = outputDirectory.appendingPathComponent("\(basename).json")
        let metadata = [
            "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "captured_at": ISO8601DateFormatter().string(from: Date()),
            "format": "plcrash",
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)

        return crashFileURL
    }

    private static func crashReportDirectory() throws -> URL {
        let appSupportRoot = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleName = Bundle.main.bundleIdentifier ?? "TransactionClassifier"
        let directory = appSupportRoot
            .appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent(storageDirectoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sessionMarkerURL() throws -> URL {
        let directory = try crashReportDirectory()
        return directory.appendingPathComponent(sessionMarkerFileName)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}
