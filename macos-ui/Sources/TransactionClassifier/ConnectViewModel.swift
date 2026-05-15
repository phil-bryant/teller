import Foundation
import Observation

// #R001: Context load and refresh hydration behavior.
// #R005: Connect action-handler behavior.
// #R010: Confirmed deletion mutation behavior.
// #R015: Session lifecycle callback behavior.
// #R020: Manual token-save validation behavior.
// #R025: Initial load, status, and error propagation behavior.

@MainActor
@Observable
final class ConnectViewModel {
    var contexts: [ConnectContext] = []
    var selectedContextKey: String?
    var activeSession: ConnectStartSession?
    var manualToken = ""
    var manualEnrollmentId = ""
    var manualInstitutionHint = ""
    var statusText = "Connect service idle."
    var errorText = ""
    var busy = false
    var showingDeleteConfirmation = false
    var lastSavedTokenPath = ""
    var setupSnapshot: TellerSetupSnapshot?
    var setupStatusText = "Setup status unavailable."
    var setupErrorText = ""
    var setupApplicationID = ""
    var setupBusy = false

    private let api: any ConnectAPI
    private let setupAPI: any TellerSetupAPI

    init(
        api: any ConnectAPI = ConnectAPIClient(),
        setupAPI: any TellerSetupAPI = TellerSetupService()
    ) {
        self.api = api
        self.setupAPI = setupAPI
    }

    var selectedContext: ConnectContext? {
        guard let selectedContextKey else { return nil }
        return contexts.first { $0.key == selectedContextKey }
    }

    func loadAll() async {
        busy = true
        defer { busy = false }
        do {
            async let statusResponse = api.fetchStatus()
            async let contextResponse = api.fetchContexts()
            let status = try await statusResponse
            contexts = try await contextResponse
            if selectedContext == nil {
                selectedContextKey = contexts.first?.key
            }
            updateStatusFromServer(status)
            try await refreshSetupStatus()
            errorText = ""
        } catch {
            errorText = error.localizedDescription
            statusText = "Connect service unavailable."
        }
    }

    func refreshSetupOnly() async {
        setupBusy = true
        defer { setupBusy = false }
        do {
            try await refreshSetupStatus()
        } catch {
            setupErrorText = error.localizedDescription
            setupStatusText = "Setup status unavailable."
        }
    }

    func saveSetupApplicationID() async {
        let normalized = setupApplicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            setupErrorText = "Application ID is required."
            return
        }
        setupBusy = true
        defer { setupBusy = false }
        do {
            let path = try await setupAPI.saveApplicationID(normalized)
            setupStatusText = "Saved application ID at \(path)."
            setupErrorText = ""
            try await refreshSetupStatus()
        } catch {
            setupErrorText = error.localizedDescription
            setupStatusText = "Saving application ID failed."
        }
    }

    func saveSetupAuthToken() async {
        let token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            setupErrorText = "Access token is required."
            return
        }
        setupBusy = true
        defer { setupBusy = false }
        do {
            let path = try await setupAPI.saveAuthToken(token)
            setupStatusText = "Saved auth token at \(path)."
            setupErrorText = ""
            manualToken = ""
            try await refreshSetupStatus()
            await refreshContexts()
        } catch {
            setupErrorText = error.localizedDescription
            setupStatusText = "Saving auth token failed."
        }
    }

    func runSetupSmokeCheck() async {
        setupBusy = true
        defer { setupBusy = false }
        do {
            let result = try await setupAPI.runSmokeCheck()
            let institutionsCount = result.institutionsCount.map(String.init) ?? "unknown"
            let accountsText = result.accountsHTTPStatus.map { "accounts=\($0)" } ?? "accounts=skipped"
            let warningText = result.warningText.isEmpty ? "" : " \(result.warningText)"
            setupStatusText = "Smoke check passed (institutions=\(result.institutionsHTTPStatus), count=\(institutionsCount), \(accountsText)).\(warningText)"
            setupErrorText = ""
            try await refreshSetupStatus()
        } catch {
            setupErrorText = error.localizedDescription
            setupStatusText = "Smoke check failed."
        }
    }

    func refreshContexts() async {
        busy = true
        defer { busy = false }
        do {
            contexts = try await api.fetchContexts()
            if selectedContext == nil {
                selectedContextKey = contexts.first?.key
            }
            errorText = ""
            statusText = "Loaded \(contexts.count) local enrollment context(s)."
        } catch {
            errorText = error.localizedDescription
            statusText = "Context refresh failed."
        }
    }

    func saveManualToken(action: ConnectAction) async {
        let normalizedToken = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnrollmentId = manualEnrollmentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstitution = manualInstitutionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        await saveToken(
            action: action,
            token: normalizedToken,
            enrollmentId: normalizedEnrollmentId,
            institutionHint: normalizedInstitution
        )
    }

    func saveCapturedToken(
        action: ConnectAction,
        targetKey: String,
        token: String,
        enrollmentId: String,
        institutionHint: String
    ) async {
        await saveToken(
            action: action,
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            enrollmentId: enrollmentId.trimmingCharacters(in: .whitespacesAndNewlines),
            institutionHint: institutionHint.trimmingCharacters(in: .whitespacesAndNewlines),
            targetKeyOverride: targetKey
        )
    }

    func startConnect(action: ConnectAction) async {
        do {
            let session = try await api.startSession(action: action, selectedContext: selectedContext)
            activeSession = session
            statusText = "Opening \(action.buttonLabel.lowercased()) flow..."
            errorText = ""
        } catch {
            activeSession = nil
            errorText = error.localizedDescription
            statusText = "Connect flow unavailable."
        }
    }

    func cancelConnect() {
        activeSession = nil
    }

    private func saveToken(
        action: ConnectAction,
        token: String,
        enrollmentId: String,
        institutionHint: String,
        targetKeyOverride: String? = nil
    ) async {
        guard !token.isEmpty else {
            errorText = "Token is required."
            return
        }
        var targetKey = ""
        if action == .reconnect {
            if let targetKeyOverride {
                targetKey = targetKeyOverride
            } else {
                guard let selectedContext else {
                    errorText = "Select a context before reconnecting."
                    return
                }
                guard selectedContext.hasEnrollmentId else {
                    errorText = "Selected context has no enrollment_id."
                    return
                }
                targetKey = selectedContext.key
            }
        }

        busy = true
        defer { busy = false }
        do {
            let response = try await api.storeToken(
                ConnectStoreTokenRequest(
                    token: token,
                    enrollmentId: enrollmentId,
                    action: action.rawValue,
                    targetKey: targetKey,
                    institutionIdHint: institutionHint
                )
            )
            contexts = try await api.fetchContexts()
            if selectedContext == nil {
                selectedContextKey = contexts.first?.key
            }
            lastSavedTokenPath = response.path
            statusText = "\(action.buttonLabel) token saved at \(response.path)."
            errorText = ""
            activeSession = nil
            if action != .reconnect {
                manualToken = ""
            }
        } catch {
            errorText = error.localizedDescription
            statusText = "\(action.buttonLabel) failed."
        }
    }

    func deleteSelectedContext() async {
        guard let selectedContext else {
            errorText = "Select a context before deleting."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let response = try await api.deleteContext(targetKey: selectedContext.key)
            contexts = response.remaining
            selectedContextKey = contexts.first?.key
            statusText = "Deleted context \(selectedContext.displayInstitutionId)."
            errorText = ""
        } catch {
            errorText = error.localizedDescription
            statusText = "Delete failed."
        }
    }

    private func updateStatusFromServer(_ status: ConnectStatusResponse) {
        lastSavedTokenPath = status.saved_path
        if !status.error.isEmpty {
            statusText = "Connect service reported an error."
            errorText = status.error
            return
        }
        if status.token_saved {
            statusText = "Latest token path: \(status.saved_path)"
        } else {
            statusText = "Ready to manage local enrollments."
        }
    }

    private func refreshSetupStatus() async throws {
        let snapshot = try await setupAPI.loadSnapshot()
        setupSnapshot = snapshot
        if setupApplicationID.isEmpty && snapshot.hasApplicationID {
            setupApplicationID = "configured"
        }
        let readiness = snapshot.isReadyForInstitutionsSmoke ? "ready" : "incomplete"
        setupStatusText = "Step 18 setup is \(readiness)."
        setupErrorText = ""
    }
}
