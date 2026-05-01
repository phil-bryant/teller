import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ConnectViewModel {
    var contexts: [ConnectContext] = []
    var selectedContextKey: String?
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
        guard !normalizedToken.isEmpty else {
            errorText = "Token is required."
            return
        }

        var targetKey = ""
        if action == .reconnect {
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

        busy = true
        defer { busy = false }
        do {
            let response = try await api.storeToken(
                ConnectStoreTokenRequest(
                    token: normalizedToken,
                    enrollmentId: normalizedEnrollmentId,
                    action: action.rawValue,
                    targetKey: targetKey,
                    institutionIdHint: normalizedInstitution
                )
            )
            contexts = try await api.fetchContexts()
            if selectedContext == nil {
                selectedContextKey = contexts.first?.key
            }
            lastSavedTokenPath = response.path
            statusText = "\(action.buttonLabel) token saved at \(response.path)."
            errorText = ""
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

    func openLegacyConnectManager() {
        guard let url = URL(string: ProcessInfo.processInfo.environment["TELLER_CONNECT_MANAGER_URL"] ?? "http://127.0.0.1:8080") else {
            errorText = "Invalid Connect manager URL."
            return
        }
        NSWorkspace.shared.open(url)
        statusText = "Opened Teller Connect manager in your browser."
        errorText = ""
    }

    private func updateStatusFromServer(_ status: ConnectStatusResponse) {
        lastSavedTokenPath = status.saved_path
        if !status.error.isEmpty {
            statusText = "Connect server reported an error."
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
