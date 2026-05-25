import AppKit
import SwiftUI
import WebKit

// #R001: Context list and refresh UI behavior.
// #R005: Connect/reconnect/add/delete action UI behavior.
// #R010: Delete confirmation dialog behavior.
// #R015: WebView session bridge behavior.
// #R020: Manual-save entry-point behavior.
// #R025: Initial load task behavior.

struct ConnectView: View {
    @Bindable var viewModel: ConnectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial Institution Connections")
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("connect-title")
            Text("Select a connection, then edit or delete it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(selection: $viewModel.selectedContextKey) {
                ForEach(viewModel.contexts) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.displayInstitutionId)
                        Text("Connection ID: \(context.displayEnrollmentId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("connect-context-row-\(context.key)")
                    .tag(Optional(context.key))
                }
            }
            .accessibilityIdentifier("connect-context-list")

            HStack(spacing: 8) {
                Button("Add") { Task { await viewModel.startConnect(action: .add) } }
                    .disabled(viewModel.busy)
                    .accessibilityIdentifier("connect-add-button")
                Button("Edit") { Task { await viewModel.startConnect(action: .reconnect) } }
                    .disabled(viewModel.busy || !(viewModel.selectedContext?.hasEnrollmentId ?? false))
                    .accessibilityIdentifier("connect-edit-button")
                Button("Delete") {
                    viewModel.showingDeleteConfirmation = true
                }
                .disabled(viewModel.busy || viewModel.selectedContext == nil)
                .accessibilityIdentifier("connect-delete-button")
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
        }
        .frame(minWidth: 760, minHeight: 520, alignment: .topLeading)
        .padding(12)
        .confirmationDialog(
            "Delete selected connection?",
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
            // Keep Connect in a large, predictable viewport so Teller's modal
            // does not collapse into an unclickable compact overlay.
            .frame(minWidth: 980, minHeight: 700)
        }
        .task {
            await viewModel.loadAll()
        }
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
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = .default()
        let webView = ConnectWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Avoid about:blank origin; Teller Connect flows can stall in embedded
        // contexts when the parent page has no trusted HTTPS origin.
        webView.loadHTMLString(
            Self.buildHTML(for: session),
            baseURL: URL(string: "https://honeydue.ai/")
        )
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
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              overflow: hidden;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #0b0d11;
              color: #ffffff;
            }
            .launcher {
              min-height: 100%;
              display: flex;
              align-items: center;
              justify-content: center;
              flex-direction: column;
              gap: 10px;
              position: relative;
              z-index: 1;
            }
            button {
              padding: 10px 14px;
              font-size: 14px;
              border-radius: 8px;
              border: 1px solid #2f79ff;
              background: #105ce7;
              color: #ffffff;
            }
            pre {
              margin: 0;
              width: min(90vw, 560px);
              white-space: pre-wrap;
              background: rgba(255, 255, 255, 0.08);
              padding: 10px;
              border-radius: 6px;
              font-size: 12px;
            }
            body.connect-opened .launcher {
              display: none;
            }
          </style>
        </head>
        <body>
          <div class="launcher">
            <h2>Teller Connect</h2>
            <p>Complete enrollment in this window.</p>
            <button id="connectButton">Open Connect</button>
            <pre id="status">Ready.</pre>
          </div>
          <script>
            const appId = \(appID);
            const environment = \(environment);
            const enrollmentId = \(enrollmentID);
            const statusEl = document.getElementById("status");
            const launcherEl = document.querySelector(".launcher");
            const bridge = (payload) => window.webkit.messageHandlers.connectBridge.postMessage(payload);
            const setStatus = (message) => {
              statusEl.textContent = message;
              bridge({ type: "debug", message });
            };
            const openConnect = () => {
              try {
                const setup = {
                  applicationId: appId,
                  environment: environment,
                  products: ["verify", "balance", "transactions", "identity"],
                  onInit: () => setStatus("Connect initialized."),
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
                  onExit: () => {
                    setStatus("Connect exited.");
                    bridge({ type: "exit" });
                  }
                };
                if (enrollmentId) setup.enrollmentId = enrollmentId;
                setStatus("Opening Teller Connect...");
                const connect = TellerConnect.setup(setup);
                connect.open();
                document.body.classList.add("connect-opened");
                setStatus("Connect modal opened.");
                if (launcherEl) launcherEl.remove();
              } catch (error) {
                bridge({ type: "error", message: String(error && error.message ? error.message : error) });
              }
            };
            document.getElementById("connectButton").addEventListener("click", openConnect);
            // Keep launch explicit so Connect opens from a user gesture path.
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

    private final class ConnectWKWebView: WKWebView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            _ = event
            return true
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
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
            case "debug":
                break
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let allowedSchemes = Set(["http", "https", "about", "data", "file", "blob"])
            let normalizedScheme = url.scheme?.lowercased() ?? ""
            if !allowedSchemes.contains(normalizedScheme) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            _ = configuration
            _ = windowFeatures
            // Teller Connect may attempt to open a new window during flow.
            // Route these requests into the same WebView instead of dropping them.
            if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
            }
            return nil
        }
    }
}
