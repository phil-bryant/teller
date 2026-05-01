#!/usr/bin/env python3
import argparse
import base64
import html
import json
import os
import threading
import time
import tempfile
import webbrowser

import requests
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import List, Dict, Optional


HOME = Path.home()
TELLER_DIR = HOME / ".teller"
APP_ID_FILE = TELLER_DIR / "application_id.txt"
AUTH_TOKEN_FILE = TELLER_DIR / "auth_token.json"
ENROLLMENT_ID_FILE = TELLER_DIR / "enrollment_id.txt"
CERT_FILE = TELLER_DIR / "certificate.pem"
KEY_FILE = TELLER_DIR / "private_key.pem"


class CaptureState:
    def __init__(
        self,
        app_id: str,
        environment: str,
        enrollment_id: str,
        auth_token_file: Path,
        enrollment_id_file: Path,
        mode: str,
        local_contexts: List[Dict[str, str]],
    ):
        self.app_id = app_id
        self.environment = environment
        self.enrollment_id = enrollment_id
        self.auth_token_file = auth_token_file
        self.enrollment_id_file = enrollment_id_file
        self.mode = mode
        self.local_contexts = local_contexts
        self.token_saved = False
        self.completed = False
        self.completion_reason = ""
        self.saved_path = str(auth_token_file)
        self.error = ""


def token_from_file(path: Path) -> str:
    if not path.is_file():
        return ""
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("current", "")
    except (OSError, json.JSONDecodeError):
        return ""


def infer_institution_id(token: str) -> str:
    if not token or not CERT_FILE.is_file() or not KEY_FILE.is_file():
        return ""
    try:
        auth = base64.b64encode(f"{token}:".encode("utf-8")).decode("utf-8")
        response = requests.get(
            "https://api.teller.io/identity",
            headers={"Authorization": f"Basic {auth}"},
            cert=(str(CERT_FILE), str(KEY_FILE)),
            timeout=8,
        )
        response.raise_for_status()
        body = response.json()
        if isinstance(body, list) and body and isinstance(body[0], dict):
            return body[0].get("account", {}).get("institution", {}).get("id", "")
    except (requests.RequestException, OSError, ValueError):
        return ""
    return ""


def load_metadata_institution_map() -> Dict[str, str]:
    metadata_path = TELLER_DIR / "enrollments.json"
    if not metadata_path.is_file():
        return {}
    try:
        payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    institution_map = {}
    if not isinstance(payload, list):
        return institution_map
    for row in payload:
        if not isinstance(row, dict):
            continue
        enrollment_id = row.get("enrollment_id", "")
        institution_id = row.get("institution_id", "")
        if enrollment_id and institution_id:
            institution_map[enrollment_id] = institution_id
    return institution_map


def discover_local_contexts() -> List[Dict[str, str]]:
    metadata_map = load_metadata_institution_map()
    contexts = []
    if AUTH_TOKEN_FILE.is_file() or ENROLLMENT_ID_FILE.is_file():
        if ENROLLMENT_ID_FILE.is_file():
            default_enrollment_id = ENROLLMENT_ID_FILE.read_text(encoding="utf-8").strip()
        else:
            default_enrollment_id = ""
        default_token = token_from_file(AUTH_TOKEN_FILE)
        default_institution = infer_institution_id(default_token) or metadata_map.get(default_enrollment_id, "")
        contexts.append(
            {
                "key": "default",
                "source": "default",
                "institution_id": default_institution,
                "enrollment_id": default_enrollment_id,
                "token_path": str(AUTH_TOKEN_FILE),
                "enrollment_path": str(ENROLLMENT_ID_FILE),
            }
        )
    for token_file in sorted(TELLER_DIR.glob("auth_token_*.json")):
        suffix = token_file.name[11:-5]
        enrollment_file = TELLER_DIR / f"enrollment_id_{suffix}.txt"
        enrollment_id = enrollment_file.read_text(encoding="utf-8").strip() if enrollment_file.is_file() else ""
        inferred_id = infer_institution_id(token_from_file(token_file)) or metadata_map.get(enrollment_id, "")
        contexts.append(
            {
                "key": f"suffix:{suffix}",
                "source": "suffix",
                "institution_id": inferred_id or suffix,
                "enrollment_id": enrollment_id,
                "token_path": str(token_file),
                "enrollment_path": str(enrollment_file),
            }
        )
    return contexts


def sanitize_suffix(raw: str) -> str:
    clean = "".join(ch.lower() if ch.isalnum() or ch == "_" else "_" for ch in raw).strip("_")
    return clean or "enrollment"


def ensure_unique_suffix(base: str) -> str:
    candidate, counter = base, 1
    while (TELLER_DIR / f"auth_token_{candidate}.json").exists() or (TELLER_DIR / f"enrollment_id_{candidate}.txt").exists():
        candidate, counter = f"{base}_{counter}", counter + 1
    return candidate


def move_to_trash(path: Path) -> Optional[str]:
    if not path.exists():
        return None
    trash_dir = Path.home() / ".Trash" / "teller-enrollment-removals"
    trash_dir.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%d-%H.%M.%S")
    destination = trash_dir / f"{path.name}.{timestamp}"
    path.rename(destination)
    return str(destination)


def find_context(local_contexts: List[Dict[str, str]], key: str) -> Optional[Dict[str, str]]:
    for row in local_contexts:
        if row.get("key") == key:
            return row
    return None


def render_contexts_html(local_contexts: List[Dict[str, str]]) -> str:
    #R075: Render known local enrollment contexts (or explicit empty state) before Connect actions.
    if not local_contexts:
        return (
            "<section class='contexts'><h2>Known Local Enrollments</h2>"
            "<p class='empty'>No local enrollment contexts found under ~/.teller yet.</p></section>"
        )
    rows = []
    for row in local_contexts:
        key = html.escape(row.get("key", ""))
        institution_id = row.get("institution_id", "") or "unknown"
        reconnect = (
            f"<button onclick=\"startReconnect('{key}')\">Reconnect</button>"
            if row.get("enrollment_id")
            else "<button disabled title='Missing enrollment_id'>Reconnect</button>"
        )
        rows.append(
            "<tr><td><code>{}</code></td><td>{}</td><td><button onclick=\"deleteContext('{}')\">Delete</button></td></tr>"
            .format(
                html.escape(institution_id),
                reconnect,
                key,
            )
        )
    return (
        "<section class='contexts'><h2>Known Local Enrollments</h2>"
        "<table><thead><tr><th>institution_id</th><th>connect</th><th>delete</th>"
        "</tr></thead><tbody>{}</tbody></table></section>".format("".join(rows))
    )


def build_html(app_id: str, environment: str, enrollment_id: str, mode: str, local_contexts: List[Dict[str, str]]) -> str:
    app_id_json = json.dumps(app_id)
    env_json = json.dumps(environment)
    enrollment_id_json = json.dumps(enrollment_id)
    mode_json = json.dumps(mode)
    contexts_html = render_contexts_html(local_contexts) if mode == "manage" else ""
    show_capture_button = mode == "capture"
    button_label = "Repair Existing Enrollment" if enrollment_id else "Connect Bank Account"
    description = "Manage enrollments below." if mode == "manage" else (
        "Click repair to restore your existing enrollment and auto-save your access token."
        if enrollment_id else "Click connect to enroll and auto-save your access token to ~/.teller/auth_token.json."
    )
    #R080: Management mode exposes add/reconnect/delete actions from the same page.
    manage_controls = (
        "<div class='controls'><button onclick='startAdd()'>Add Enrollment</button></div>" if mode == "manage" else ""
    )
    connect_button = f"<button id='connect'>{button_label}</button>" if show_capture_button else ""
    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Teller Connect Token Capture</title>
  <script src="https://cdn.teller.io/connect/connect.js"></script>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      max-width: 720px; margin: 48px auto; padding: 0 20px; }}
    .controls {{ margin: 12px 0; }}
    .contexts {{ margin: 16px 0 20px 0; padding: 12px; border: 1px solid #d0d7de; border-radius: 8px; background: #f6f8fa; }}
    .contexts h2 {{ margin: 0 0 8px 0; font-size: 16px; }}
    .contexts table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
    .contexts th, .contexts td {{ border-bottom: 1px solid #d0d7de; text-align: left; padding: 8px 6px; }}
    .contexts .empty {{ margin: 0; }}
    button {{ padding: 10px 16px; font-size: 14px; }}
    pre {{ background: #f6f8fa; padding: 12px; border-radius: 6px; overflow-x: auto; }}
  </style>
</head>
<body>
  <h1>Teller Connect</h1>
  <p>{description}</p>
  {manage_controls}
  {contexts_html}
  {connect_button}
  <pre id="status">Ready.</pre>
  <script>
    const statusEl = document.getElementById('status');
    const connectBtn = document.getElementById('connect');
    const appId = {app_id_json};
    const env = {env_json};
    const mode = {mode_json};
    const enrollmentId = {enrollment_id_json};

    const setStatus = (msg) => {{
      statusEl.textContent = msg;
    }};

    const openConnect = (action, targetKey, selectedEnrollmentId) => {{
      const connectEnrollmentId = selectedEnrollmentId || '';
      setStatus(connectEnrollmentId ? 'Opening Teller Connect repair flow...' : 'Opening Teller Connect...');
      const setup = {{
        applicationId: appId,
        environment: env,
        products: ["verify", "balance", "transactions", "identity"],
        onSuccess: async (enrollment) => {{
          try {{
            const token = enrollment.accessToken;
            const newEnrollmentId = enrollment?.enrollment?.id || "";
            const institutionIdHint = enrollment?.enrollment?.institution?.id || enrollment?.institution?.id || "";
            const resp = await fetch('/api/store-token', {{
              method: 'POST',
              headers: {{ 'Content-Type': 'application/json' }},
              body: JSON.stringify({{ token, enrollmentId: newEnrollmentId, action, targetKey, institutionIdHint }})
            }});
            const data = await resp.json();
            if (!resp.ok) {{
              throw new Error(data.error || 'Failed to save token');
            }}
            if (action === 'add') setStatus('Added enrollment. You can close this tab.');
            else if (action === 'reconnect') setStatus('Reconnected enrollment. You can close this tab.');
            else setStatus('Saved token successfully. You can close this tab.');
          }} catch (err) {{
            setStatus(`Error saving token: ${{err.message}}`);
          }}
        }},
        onExit: () => {{
          setStatus('Connect exited.');
        }}
      }};
      if (connectEnrollmentId) setup.enrollmentId = connectEnrollmentId;
      TellerConnect.setup(setup).open();
    }};

    const startAdd = () => openConnect('add', '', '');
    const startReconnect = async (targetKey) => {{
      const resp = await fetch('/api/contexts');
      const data = await resp.json();
      const row = (data.contexts || []).find((item) => item.key === targetKey);
      if (!row || !row.enrollment_id) {{
        setStatus('Cannot reconnect: missing enrollment context.');
        return;
      }}
      openConnect('reconnect', targetKey, row.enrollment_id);
    }};

    const deleteContext = async (targetKey) => {{
      if (!confirm('Delete this local enrollment context?')) return;
      const resp = await fetch('/api/delete-context', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ targetKey }})
      }});
      const data = await resp.json();
      if (!resp.ok) {{
        setStatus(`Delete failed: ${{data.error || 'Unknown error'}}`);
        return;
      }}
      setStatus('Enrollment context deleted. You can close this tab.');
    }};

    if (connectBtn) connectBtn.addEventListener('click', () => openConnect('capture', '', enrollmentId));
    if (mode === 'manage') setStatus('Select an enrollment action: reconnect, delete, or add.');
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
            body = build_html(
                self.server.capture_state.app_id,
                self.server.capture_state.environment,
                self.server.capture_state.enrollment_id,
                self.server.capture_state.mode,
                self.server.capture_state.local_contexts,
            ).encode("utf-8")
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

        if self.path == "/api/contexts":
            self._send_json(200, {"contexts": self.server.capture_state.local_contexts})
            return

        self._send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path not in ["/api/store-token", "/api/delete-context"]:
            self._send_json(404, {"error": "not found"})
            return

        content_len = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_len) if content_len > 0 else b"{}"

        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid json"})
            return

        if self.path == "/api/delete-context":
            #R080: Delete selected local enrollment context only in management mode.
            target_key = payload.get("targetKey", "")
            if self.server.capture_state.mode != "manage":
                self._send_json(400, {"error": "delete is only available in management mode"})
                return
            context = find_context(self.server.capture_state.local_contexts, target_key)
            if not context:
                self._send_json(404, {"error": "context not found"})
                return
            token_path = Path(context.get("token_path", ""))
            enrollment_path = Path(context.get("enrollment_path", ""))
            moved_token = move_to_trash(token_path)
            moved_enrollment = move_to_trash(enrollment_path)
            self.server.capture_state.local_contexts = discover_local_contexts()
            self.server.capture_state.completed = True
            self.server.capture_state.completion_reason = "delete"
            self._send_json(200, {
                "ok": True,
                "moved_token": moved_token,
                "moved_enrollment": moved_enrollment,
                "remaining": self.server.capture_state.local_contexts,
            })
            return

        token = payload.get("token", "")
        enrollment_id = payload.get("enrollmentId", "")
        action = payload.get("action", "capture")
        target_key = payload.get("targetKey", "")
        institution_hint = payload.get("institutionIdHint", "")
        if not token:
            self._send_json(400, {"error": "token is required"})
            return

        try:
            TELLER_DIR.mkdir(parents=True, exist_ok=True)
            # Owner only on the directory; no group/other read, write, or search (contrast: 0o644 / world-readable).
            # Token/enrollment files below use 0o400: owner read/write only, not group/other readable or executable.
            # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions
            os.chmod(TELLER_DIR, 0o700)
            auth_token_file = self.server.capture_state.auth_token_file
            enrollment_id_file = self.server.capture_state.enrollment_id_file
            if self.server.capture_state.mode == "manage":
                if action == "reconnect":
                    #R080: Reconnect updates only the selected context file pair.
                    context = find_context(self.server.capture_state.local_contexts, target_key)
                    if not context:
                        self._send_json(404, {"error": "context not found"})
                        return
                    auth_token_file = Path(context["token_path"])
                    enrollment_id_file = Path(context["enrollment_path"])
                elif action == "add":
                    #R080: Add writes to a new unique suffixed context without overwriting existing contexts.
                    suffix = ensure_unique_suffix(sanitize_suffix(institution_hint or enrollment_id))
                    auth_token_file = TELLER_DIR / f"auth_token_{suffix}.json"
                    enrollment_id_file = TELLER_DIR / f"enrollment_id_{suffix}.txt"
            auth_token_file.parent.mkdir(parents=True, exist_ok=True)
            enrollment_id_file.parent.mkdir(parents=True, exist_ok=True)

            fd, tmp_path = tempfile.mkstemp(dir=str(TELLER_DIR), prefix="auth_token.", suffix=".json")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump({"current": token}, f)
                    f.write("\n")
                os.chmod(tmp_path, 0o400)
                os.replace(tmp_path, auth_token_file)
            finally:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)

            if enrollment_id:
                fd, tmp_path = tempfile.mkstemp(dir=str(TELLER_DIR), prefix="enrollment_id.", suffix=".txt")
                try:
                    with os.fdopen(fd, "w", encoding="utf-8") as f:
                        f.write(enrollment_id)
                        f.write("\n")
                    os.chmod(tmp_path, 0o400)
                    os.replace(tmp_path, enrollment_id_file)
                finally:
                    if os.path.exists(tmp_path):
                        os.remove(tmp_path)

            self.server.capture_state.token_saved = True
            self.server.capture_state.completed = True
            self.server.capture_state.completion_reason = action
            self.server.capture_state.error = ""
            self.server.capture_state.local_contexts = discover_local_contexts()
            self._send_json(200, {"ok": True, "path": str(auth_token_file), "enrollment_id_path": str(enrollment_id_file)})
        except Exception as exc:
            self.server.capture_state.error = str(exc)
            self._send_json(500, {"error": str(exc)})

    def log_message(self, _format: str, *_args):
        return


def main():
    parser = argparse.ArgumentParser(description="Run local Teller Connect token capture server.")
    parser.add_argument("--port", type=int, default=int(os.getenv("PORT", "8080")))
    parser.add_argument("--environment", default=os.getenv("CONNECT_ENVIRONMENT", "development"))
    parser.add_argument("--enrollment-id", default=os.getenv("ENROLLMENT_ID", ""))
    parser.add_argument("--mode", choices=["capture", "manage"], default=os.getenv("CONNECT_CAPTURE_MODE", "capture"))
    # R065/R070: caller can target reconnect/add writes to specific enrollment context files.
    parser.add_argument("--auth-token-file", default=os.getenv("AUTH_TOKEN_OUTPUT_FILE", str(AUTH_TOKEN_FILE)))
    parser.add_argument("--enrollment-id-file", default=os.getenv("ENROLLMENT_ID_OUTPUT_FILE", str(ENROLLMENT_ID_FILE)))
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--stay-alive", action="store_true")
    args = parser.parse_args()

    if not APP_ID_FILE.is_file():
        raise SystemExit(f"Missing application id file: {APP_ID_FILE}")

    app_id = APP_ID_FILE.read_text(encoding="utf-8").strip()
    if not app_id:
        raise SystemExit(f"Application id is empty in: {APP_ID_FILE}")

    auth_token_file = Path(args.auth_token_file).expanduser()
    enrollment_id_file = Path(args.enrollment_id_file).expanduser()
    local_contexts = discover_local_contexts()
    state = CaptureState(
        app_id=app_id,
        environment=args.environment,
        enrollment_id=args.enrollment_id,
        auth_token_file=auth_token_file,
        enrollment_id_file=enrollment_id_file,
        mode=args.mode,
        local_contexts=local_contexts,
    )
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.capture_state = state

    print("Teller Connect token capture server running")
    print(f"- URL: http://localhost:{args.port}")
    print(f"- Environment: {args.environment}")
    print(f"- Mode: {args.mode}")
    if args.enrollment_id:
        print(f"- Repair Enrollment ID: {args.enrollment_id}")
    elif local_contexts:
        print(f"- Known local enrollments shown in UI: {len(local_contexts)}")
    print(f"- Output token file: {auth_token_file}")
    print(f"- Output enrollment file: {enrollment_id_file}")
    print("Waiting for enrollment...")

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    if not args.no_open:
        webbrowser.open(f"http://localhost:{args.port}")

    try:
        while not state.completed or args.stay_alive:
            time.sleep(0.25)
    except KeyboardInterrupt:
        print("\nStopped before token was captured.")
    finally:
        server.shutdown()
        server.server_close()

    if state.token_saved:
        print(f"✅ Token saved to {auth_token_file}")
    elif state.completion_reason == "delete":
        print("✅ Enrollment context deleted.")


if __name__ == "__main__":
    main()
