#!/usr/bin/env python3
import argparse
import json
import os
import threading
import time
import tempfile
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HOME = Path.home()
TELLER_DIR = HOME / ".teller"
APP_ID_FILE = TELLER_DIR / "application_id.txt"
AUTH_TOKEN_FILE = TELLER_DIR / "auth_token.json"


class CaptureState:
    def __init__(self, app_id: str, environment: str):
        self.app_id = app_id
        self.environment = environment
        self.token_saved = False
        self.saved_path = str(AUTH_TOKEN_FILE)
        self.error = ""


def build_html(app_id: str, environment: str) -> str:
    app_id_json = json.dumps(app_id)
    env_json = json.dumps(environment)
    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Teller Connect Token Capture</title>
  <script src="https://cdn.teller.io/connect/connect.js"></script>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 720px; margin: 48px auto; padding: 0 20px; }}
    button {{ padding: 10px 16px; font-size: 14px; }}
    pre {{ background: #f6f8fa; padding: 12px; border-radius: 6px; overflow-x: auto; }}
  </style>
</head>
<body>
  <h1>Teller Connect</h1>
  <p>Click connect to enroll and auto-save your access token to <code>~/.teller/auth_token.json</code>.</p>
  <button id="connect">Connect Bank Account</button>
  <pre id="status">Ready.</pre>
  <script>
    const statusEl = document.getElementById('status');
    const connectBtn = document.getElementById('connect');
    const appId = {app_id_json};
    const env = {env_json};

    const setStatus = (msg) => {{
      statusEl.textContent = msg;
    }};

    connectBtn.addEventListener('click', () => {{
      setStatus('Opening Teller Connect...');
      TellerConnect.setup({{
        applicationId: appId,
        environment: env,
        products: ["verify", "balance", "transactions", "identity"],
        onSuccess: async (enrollment) => {{
          try {{
            const token = enrollment.accessToken;
            const resp = await fetch('/api/store-token', {{
              method: 'POST',
              headers: {{ 'Content-Type': 'application/json' }},
              body: JSON.stringify({{ token }})
            }});
            const data = await resp.json();
            if (!resp.ok) {{
              throw new Error(data.error || 'Failed to save token');
            }}
            setStatus('Saved token successfully. You can close this tab.');
          }} catch (err) {{
            setStatus(`Error saving token: ${{err.message}}`);
          }}
        }},
        onExit: () => {{
          setStatus('Connect exited.');
        }}
      }}).open();
    }});
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status_code: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            body = build_html(self.server.capture_state.app_id, self.server.capture_state.environment).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/api/status":
            self._send_json(
                200,
                {
                    "token_saved": self.server.capture_state.token_saved,
                    "saved_path": self.server.capture_state.saved_path,
                    "error": self.server.capture_state.error,
                },
            )
            return

        self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/store-token":
            self._send_json(404, {"error": "not found"})
            return

        content_len = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_len) if content_len > 0 else b"{}"

        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid json"})
            return

        token = payload.get("token", "")
        if not token:
            self._send_json(400, {"error": "token is required"})
            return

        try:
            TELLER_DIR.mkdir(parents=True, exist_ok=True)
            os.chmod(TELLER_DIR, 0o700)

            fd, tmp_path = tempfile.mkstemp(dir=str(TELLER_DIR), prefix="auth_token.", suffix=".json")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump({"current": token}, f)
                    f.write("\n")
                os.chmod(tmp_path, 0o400)
                os.replace(tmp_path, AUTH_TOKEN_FILE)
            finally:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)

            self.server.capture_state.token_saved = True
            self.server.capture_state.error = ""
            self._send_json(200, {"ok": True, "path": str(AUTH_TOKEN_FILE)})
        except Exception as exc:
            self.server.capture_state.error = str(exc)
            self._send_json(500, {"error": str(exc)})

    def log_message(self, _format: str, *_args):
        return


def main():
    parser = argparse.ArgumentParser(description="Run local Teller Connect token capture server.")
    parser.add_argument("--port", type=int, default=int(os.getenv("PORT", "8080")))
    parser.add_argument("--environment", default=os.getenv("CONNECT_ENVIRONMENT", "development"))
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()

    if not APP_ID_FILE.is_file():
        raise SystemExit(f"Missing application id file: {APP_ID_FILE}")

    app_id = APP_ID_FILE.read_text(encoding="utf-8").strip()
    if not app_id:
        raise SystemExit(f"Application id is empty in: {APP_ID_FILE}")

    state = CaptureState(app_id=app_id, environment=args.environment)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.capture_state = state

    print("Teller Connect token capture server running")
    print(f"- URL: http://localhost:{args.port}")
    print(f"- Environment: {args.environment}")
    print(f"- Output: {AUTH_TOKEN_FILE}")
    print("Waiting for enrollment...")

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    if not args.no_open:
        webbrowser.open(f"http://localhost:{args.port}")

    try:
        while not state.token_saved:
            time.sleep(0.25)
    except KeyboardInterrupt:
        print("\nStopped before token was captured.")
    finally:
        server.shutdown()
        server.server_close()

    if state.token_saved:
        print(f"✅ Token saved to {AUTH_TOKEN_FILE}")


if __name__ == "__main__":
    main()
