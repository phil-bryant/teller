import Foundation

// #R020: Return stable Teller setup snapshot and smoke-check responses for UI testing.

actor UITestingFixtureSetupAPI: TellerSetupAPI {
    func loadSnapshot() async throws -> TellerSetupSnapshot {
        TellerSetupSnapshot(
            tellerDirectory: "/Users/test/.teller",
            applicationIDPath: "/Users/test/.teller/application_id.txt",
            certificatePath: "/Users/test/.teller/certificate.pem",
            privateKeyPath: "/Users/test/.teller/private_key.pem",
            authTokenPath: "/Users/test/.teller/auth_token.json",
            hasApplicationID: true,
            hasCertificate: true,
            hasPrivateKey: true,
            hasAuthToken: true
        )
    }

    func saveApplicationID(_ applicationID: String) async throws -> String {
        "/Users/test/.teller/application_id.txt"
    }

    func saveAuthToken(_ token: String) async throws -> String {
        "/Users/test/.teller/auth_token.json"
    }

    func runSmokeCheck() async throws -> TellerSmokeCheckResult {
        TellerSmokeCheckResult(
            institutionsHTTPStatus: 200,
            institutionsCount: 1,
            accountsHTTPStatus: 200,
            warningText: ""
        )
    }
}
