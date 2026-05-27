import Foundation

/// CSS for the Teller Connect WKWebView shell. Held as a single `static let`
/// (not a function) so Lizard does not see this multi-line literal as part of
/// any function body.
enum ConnectWebFlowStyles {
    static let css: String = """
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
    """
}
