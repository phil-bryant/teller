import SwiftUI
import WebKit

// #R001 #R005 #R010 #R015 #R020 #R025
// ConnectView requirement tags are mapped to UI behavior in this file and its view model:
// - #R001 contexts list + refresh, #R005 connect/reconnect/add/delete actions,
// - #R010 delete confirmation dialog, #R015 WebView bridge flow, #R020 manual-save entry points, #R025 initial load task.

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
                }
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect via Native WebView").font(.headline)
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
                    Button("Connect") { Task { await viewModel.startConnect(action: .capture) } }
                        .disabled(viewModel.busy)
                        .accessibilityIdentifier("connect-capture-button")
                    Button("Reconnect Selected") { Task { await viewModel.startConnect(action: .reconnect) } }
                        .disabled(viewModel.busy || !(viewModel.selectedContext?.hasEnrollmentId ?? false))
                        .accessibilityIdentifier("connect-reconnect-button")
                    Button("Add Enrollment") { Task { await viewModel.startConnect(action: .add) } }
                        .disabled(viewModel.busy)
                        .accessibilityIdentifier("connect-add-button")
                }
                Button("Save Manual Token") {
                    Task { await viewModel.saveManualToken(action: .capture) }
                }
                .disabled(viewModel.busy || viewModel.manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("connect-manual-save-button")

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
        .sheet(item: $viewModel.activeSession) { session in
            ConnectWebFlowView(
                session: session,
                onSuccess: { token, enrollmentId, institutionHint in
                    Task {
                        await viewModel.saveCapturedToken(
                            action: session.action,
                            targetKey: session.targetKey,
                            token: token,
                            enrollmentId: enrollmentId,
                            institutionHint: institutionHint
                        )
                    }
                },
                onExit: {
                    viewModel.cancelConnect()
                },
                onFailure: { message in
                    viewModel.errorText = message
                    viewModel.cancelConnect()
                }
            )
        }
        .task {
            await viewModel.loadAll()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connect-root")
    }
}

private struct ConnectWebFlowView: NSViewRepresentable {
    let session: ConnectStartSession
    let onSuccess: @MainActor (String, String, String) -> Void
    let onExit: @MainActor () -> Void
    let onFailure: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess, onExit: onExit, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "connectBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.buildHTML(for: session), baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        _ = context
        _ = nsView
    }

    private static func buildHTML(for session: ConnectStartSession) -> String {
        let appID = jsonLiteral(session.applicationId)
        let environment = jsonLiteral(session.environment)
        let enrollmentID = jsonLiteral(session.enrollmentId)
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Teller Connect</title>
          <script src="https://cdn.teller.io/connect/connect.js"></script>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 16px; }
            button { padding: 10px 14px; font-size: 14px; }
            pre { margin-top: 12px; background: #f6f8fa; padding: 10px; border-radius: 6px; }
          </style>
        </head>
        <body>
          <h2>Teller Connect</h2>
          <p>Complete enrollment in this window.</p>
          <button id="connectButton">Open Connect</button>
          <pre id="status">Ready.</pre>
          <script>
            const appId = \(appID);
            const environment = \(environment);
            const enrollmentId = \(enrollmentID);
            const statusEl = document.getElementById("status");
            const bridge = (payload) => window.webkit.messageHandlers.connectBridge.postMessage(payload);
            const setStatus = (message) => { statusEl.textContent = message; };
            const openConnect = () => {
              const setup = {
                applicationId: appId,
                environment: environment,
                products: ["verify", "balance", "transactions", "identity"],
                onSuccess: (enrollment) => {
                  const token = enrollment?.accessToken || "";
                  const enrollmentIdValue = enrollment?.enrollment?.id || "";
                  const institutionHint = enrollment?.enrollment?.institution?.id || enrollment?.institution?.id || "";
                  if (!token) {
                    bridge({ type: "error", message: "Missing access token from Teller Connect." });
                    return;
                  }
                  bridge({ type: "success", token, enrollmentId: enrollmentIdValue, institutionHint });
                },
                onExit: () => bridge({ type: "exit" })
              };
              if (enrollmentId) setup.enrollmentId = enrollmentId;
              setStatus("Opening Teller Connect...");
              TellerConnect.setup(setup).open();
            };
            document.getElementById("connectButton").addEventListener("click", openConnect);
            window.addEventListener("load", () => setTimeout(openConnect, 100));
          </script>
        </body>
        </html>
        """
    }

    private static func jsonLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let arrayString = String(data: data, encoding: .utf8),
              arrayString.count >= 2 else {
            return "\"\""
        }
        return String(arrayString.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onSuccess: @MainActor (String, String, String) -> Void
        let onExit: @MainActor () -> Void
        let onFailure: @MainActor (String) -> Void

        init(
            onSuccess: @escaping @MainActor (String, String, String) -> Void,
            onExit: @escaping @MainActor () -> Void,
            onFailure: @escaping @MainActor (String) -> Void
        ) {
            self.onSuccess = onSuccess
            self.onExit = onExit
            self.onFailure = onFailure
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            _ = userContentController
            guard let payload = message.body as? [String: Any], let type = payload["type"] as? String else {
                Task { @MainActor in onFailure("Invalid message from Connect WebView.") }
                return
            }
            switch type {
            case "success":
                let token = payload["token"] as? String ?? ""
                let enrollmentId = payload["enrollmentId"] as? String ?? ""
                let institutionHint = payload["institutionHint"] as? String ?? ""
                Task { @MainActor in onSuccess(token, enrollmentId, institutionHint) }
            case "exit":
                Task { @MainActor in onExit() }
            case "error":
                let message = payload["message"] as? String ?? "Connect flow failed."
                Task { @MainActor in onFailure(message) }
            default:
                Task { @MainActor in onFailure("Unknown message from Connect WebView.") }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            _ = webView
            _ = navigation
            Task { @MainActor in onFailure(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            _ = webView
            _ = navigation
            Task { @MainActor in onFailure(error.localizedDescription) }
        }
    }
}
