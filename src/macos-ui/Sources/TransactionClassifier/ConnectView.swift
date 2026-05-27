import AppKit
import SwiftUI
import WebKit

// #R001: Context list and refresh UI behavior.
// #R005: Connect/reconnect/add/delete action UI behavior.
// #R010: Delete confirmation dialog behavior.
// #R015: WebView session bridge behavior.
// #R020: Manual-save entry-point behavior.
// #R025: Initial load task behavior.
// #R030: Connect Add/Edit sheet renders explicit ESC back-navigation hint.

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
        ConnectWebFlowHTML.render(for: session)
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
