import Foundation
import Observation

// #R001 #R005 #R010 #R015 #R020 #R025
// ConnectViewModel requirement tags are mapped to state-management behavior:
// - #R001 load/refresh context hydration, #R005 action handlers, #R010 confirmed deletion mutation,
// - #R015 session lifecycle callbacks, #R020 manual token save validation, #R025 initial load/status/error propagation.

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

    private let api: any ConnectAPI

    init(api: any ConnectAPI = ConnectAPIClient()) {
        self.api = api
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
            errorText = ""
        } catch {
            errorText = error.localizedDescription
            statusText = "Connect service unavailable."
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
}
