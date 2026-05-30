import Foundation

/// Composes the HTML/CSS/JS source for the in-app Teller Connect WKWebView shell.
///
/// CSS rules and JS object literals (which contain `{`/`}` characters) live in
/// sibling files (`ConnectWebFlowStyles.swift`, `ConnectWebFlowScript.swift`)
/// so this file's Swift function bodies stay free of raw curly braces inside
/// string literals — that keeps Lizard's heuristic Swift parser from
/// over-counting the function span when it can't tell a CSS `{` apart from a
/// Swift block `{`.
enum ConnectWebFlowHTML {
    static func render(for session: ConnectStartSession) -> String {
        let appID = jsonLiteral(session.applicationId)
        let environment = jsonLiteral(session.environment)
        let enrollmentID = jsonLiteral(session.enrollmentId)
        let sessionNonce = jsonLiteral(session.sessionNonce)
        let script = ConnectWebFlowScript.javaScript(
            appID: appID,
            environment: environment,
            enrollmentID: enrollmentID,
            sessionNonce: sessionNonce
        )
        return Self.htmlTemplate(styles: ConnectWebFlowStyles.css, script: script)
    }

    private static func htmlTemplate(styles: String, script: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Teller Connect</title>
          <script src="https://cdn.teller.io/connect/connect.js"></script>
          <style>\(styles)</style>
        </head>
        <body>
          <div class="launcher">
            <h2>Teller Connect</h2>
            <p>Complete enrollment in this window.</p>
            <p>Press ESC to go back.</p>
            <button id="connectButton">Open Connect</button>
            <pre id="status">Ready.</pre>
          </div>
          <script>\(script)</script>
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
}
