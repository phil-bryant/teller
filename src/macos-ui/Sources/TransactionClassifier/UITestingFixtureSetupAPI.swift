import Foundation

#if DEBUG
// #R020: Return a stable Teller setup snapshot for UI testing.

actor UITestingFixtureSetupAPI: TellerSetupAPI {
    func loadSnapshot() async throws -> TellerSetupSnapshot {
        TellerSetupSnapshot(
            hasApplicationID: true,
            hasCertificate: true,
            hasPrivateKey: true,
            hasAuthToken: true
        )
    }
}
#endif
