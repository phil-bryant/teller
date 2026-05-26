import Foundation
import Security

enum LocalClassifierTLS {
    static func defaultCertPath() -> String {
        if let env = ProcessInfo.processInfo.environment["TELLER_CLASSIFIER_TLS_CERT_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return NSHomeDirectory() + "/.teller/classifier-localhost-cert.pem"
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1" {
            return true
        }
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            return isLoopbackHost(String(normalized.dropFirst().dropLast()))
        }
        return false
    }

    static func shouldPinLocalCert(for url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && isLoopbackHost(url.host ?? "")
    }

    static func loadPinnedCertificate(from path: String) -> SecCertificate? {
        guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let derData = Data(base64Encoded: base64) else {
            return nil
        }
        return SecCertificateCreateWithData(nil, derData as CFData)
    }
}

final class LocalClassifierTLSSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertPath: String

    init(pinnedCertPath: String = LocalClassifierTLS.defaultCertPath()) {
        self.pinnedCertPath = pinnedCertPath
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              LocalClassifierTLS.isLoopbackHost(challenge.protectionSpace.host),
              let pinnedCert = LocalClassifierTLS.loadPinnedCertificate(from: pinnedCertPath) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, [pinnedCert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        if SecTrustEvaluateWithError(serverTrust, nil) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
