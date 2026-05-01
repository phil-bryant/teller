import SwiftUI

struct ConnectView: View {
    @Bindable var viewModel: ConnectViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Local Enrollment Contexts").font(.headline)
                    Spacer()
                    Button("Refresh") { Task { await viewModel.refreshContexts() } }
                        .disabled(viewModel.busy)
                        .accessibilityIdentifier("connect-refresh-button")
                }
                List(selection: $viewModel.selectedContextKey) {
                    ForEach(viewModel.contexts) { context in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.displayInstitutionId)
                            Text(context.displayEnrollmentId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(context.key))
                    }
                }
                .accessibilityIdentifier("connect-context-list")
                HStack(spacing: 8) {
                    Button("Delete Selected") {
                        viewModel.showingDeleteConfirmation = true
                    }
                    .disabled(viewModel.busy || viewModel.selectedContext == nil)
                    .accessibilityIdentifier("connect-delete-button")

                    Button("Open Browser Connect") {
                        viewModel.openLegacyConnectManager()
                    }
                    .disabled(viewModel.busy)
                    .accessibilityIdentifier("connect-open-browser-button")
                }
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)

            VStack(alignment: .leading, spacing: 10) {
                Text("Capture or Repair Token").font(.headline)
                SecureField("access token", text: $viewModel.manualToken)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connect-token-field")
                TextField("enrollment id (optional for add/capture)", text: $viewModel.manualEnrollmentId)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connect-enrollment-id-field")
                TextField("institution id hint (optional, used for add suffix)", text: $viewModel.manualInstitutionHint)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connect-institution-hint-field")

                HStack(spacing: 8) {
                    Button("Connect") { Task { await viewModel.saveManualToken(action: .capture) } }
                        .disabled(viewModel.busy)
                        .accessibilityIdentifier("connect-capture-button")
                    Button("Reconnect Selected") { Task { await viewModel.saveManualToken(action: .reconnect) } }
                        .disabled(viewModel.busy || !(viewModel.selectedContext?.hasEnrollmentId ?? false))
                        .accessibilityIdentifier("connect-reconnect-button")
                    Button("Add Enrollment") { Task { await viewModel.saveManualToken(action: .add) } }
                        .disabled(viewModel.busy)
                        .accessibilityIdentifier("connect-add-button")
                }

                if !viewModel.errorText.isEmpty {
                    Text(viewModel.errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("connect-error-banner")
                } else {
                    Text(viewModel.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("connect-status-text")
                }
                if !viewModel.lastSavedTokenPath.isEmpty {
                    Text("Token path: \(viewModel.lastSavedTokenPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("connect-token-path")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .confirmationDialog(
            "Delete selected local enrollment context?",
            isPresented: $viewModel.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await viewModel.deleteSelectedContext() } }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await viewModel.loadAll()
        }
        .accessibilityIdentifier("connect-root")
    }
}
