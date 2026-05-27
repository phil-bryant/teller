import Foundation

/// JavaScript that powers the Teller Connect launcher WKWebView. Built in a
/// dedicated file so the embedded JS object literals do not pollute Lizard's
/// brace counting for the renderer in `ConnectWebFlowHTML.swift`.
enum ConnectWebFlowScript {
    static func javaScript(appID: String, environment: String, enrollmentID: String) -> String {
        return """
        \(prelude(appID: appID, environment: environment, enrollmentID: enrollmentID))
        \(setupBlock)
        """
    }

    private static func prelude(appID: String, environment: String, enrollmentID: String) -> String {
        return """
        const appId = \(appID);
        const environment = \(environment);
        const enrollmentId = \(enrollmentID);
        const statusEl = document.getElementById("status");
        const launcherEl = document.querySelector(".launcher");
        const bridge = (payload) => window.webkit.messageHandlers.connectBridge.postMessage(payload);
        """
    }

    private static let setupBlock: String = """
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
    """
}
