import Foundation
import XCTest
@testable import TransactionClassifier

final class LocalClassifierTLSTests: XCTestCase {
    func testDefaultCertPathUsesHomeTellerDefault() {
        // #R020-T01
        unsetenv("TELLER_CLASSIFIER_TLS_CERT_FILE")
        let path = LocalClassifierTLS.defaultCertPath()
        XCTAssertTrue(path.hasSuffix("/.teller/classifier-localhost-cert.pem"))
    }

    func testDefaultCertPathHonorsEnvironmentOverride() {
        // #R020-T02
        setenv("TELLER_CLASSIFIER_TLS_CERT_FILE", "/tmp/custom-cert.pem", 1)
        defer { unsetenv("TELLER_CLASSIFIER_TLS_CERT_FILE") }
        XCTAssertEqual(LocalClassifierTLS.defaultCertPath(), "/tmp/custom-cert.pem")
    }

    func testLoopbackHostDetection() {
        // #R020-T03
        XCTAssertTrue(LocalClassifierTLS.isLoopbackHost("127.0.0.1"))
        XCTAssertTrue(LocalClassifierTLS.isLoopbackHost("localhost"))
        XCTAssertTrue(LocalClassifierTLS.isLoopbackHost("::1"))
        XCTAssertTrue(LocalClassifierTLS.isLoopbackHost("[::1]"))
        XCTAssertFalse(LocalClassifierTLS.isLoopbackHost("example.com"))
    }

    func testShouldPinLocalCertOnlyForLoopbackHTTPS() {
        // #R020-T04
        guard let loopbackHTTPSURL = URL(string: "https://127.0.0.1:8787"),
              let loopbackHTTPURL = URL(string: "http://127.0.0.1:8787"),
              let remoteHTTPSURL = URL(string: "https://example.com") else {
            XCTFail("Failed to build test URLs")
            return
        }
        XCTAssertTrue(LocalClassifierTLS.shouldPinLocalCert(for: loopbackHTTPSURL))
        XCTAssertFalse(LocalClassifierTLS.shouldPinLocalCert(for: loopbackHTTPURL))
        XCTAssertFalse(LocalClassifierTLS.shouldPinLocalCert(for: remoteHTTPSURL))
    }

    func testLoadPinnedCertificateFromInstalledDefaultCert() throws {
        // #R020-T05
        let certPath = LocalClassifierTLS.defaultCertPath()
        guard FileManager.default.fileExists(atPath: certPath) else {
            throw XCTSkip("Default classifier TLS cert is not installed at \(certPath)")
        }
        XCTAssertNotNil(LocalClassifierTLS.loadPinnedCertificate(from: certPath))
    }
}
