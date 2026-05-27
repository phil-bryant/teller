#! /usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path
from ipaddress import ip_address

import uvicorn

REPO_ROOT = Path(__file__).resolve().parent
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from teller.teller_classification_api import create_app  # noqa: E402

_WRITE_TOKEN_PSA_ITEM = "TELLER_CLASSIFIER_WRITE_TOKEN"
_DEFAULT_HOST = "127.0.0.1"
_DEFAULT_PORT = 8787
_DEFAULT_HTTPS_CERT = str(Path.home() / ".teller" / "classifier-localhost-cert.pem")
_DEFAULT_HTTPS_KEY = str(Path.home() / ".teller" / "classifier-localhost-key.pem")


def require_write_token():
    #R010: Resolve classifier write token from 1psa before serving.
    try:
        result = subprocess.run(
            ["1psa", "-p", _WRITE_TOKEN_PSA_ITEM],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("1psa is required to resolve classifier write token") from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Unable to resolve write token from 1psa item {_WRITE_TOKEN_PSA_ITEM}") from exc
    if not result.stdout.strip():
        raise RuntimeError(f"1psa item {_WRITE_TOKEN_PSA_ITEM} returned an empty write token")


def _env_flag(name: str, default: bool = False) -> bool:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def _is_local_bind_host(host: str) -> bool:
    normalized = host.strip().lower()
    if normalized in {"localhost", "127.0.0.1", "::1"}:
        return True
    try:
        parsed = ip_address(normalized)
    except ValueError:
        return False
    return parsed.is_loopback


def _resolve_transport() -> tuple[str, str | None, str | None]:
    #R015: Always require HTTPS with local TLS cert/key files.
    certfile = os.environ.get("TELLER_CLASSIFIER_TLS_CERT_FILE", _DEFAULT_HTTPS_CERT).strip()
    keyfile = os.environ.get("TELLER_CLASSIFIER_TLS_KEY_FILE", _DEFAULT_HTTPS_KEY).strip()
    if not certfile or not keyfile:
        raise RuntimeError(
            "HTTPS mode requires TELLER_CLASSIFIER_TLS_CERT_FILE and TELLER_CLASSIFIER_TLS_KEY_FILE "
            "(run ./04_install_classifier_api_tls.sh to install local cert/key files)."
        )
    cert_path = Path(certfile)
    key_path = Path(keyfile)
    if not cert_path.is_file() or not key_path.is_file():
        raise RuntimeError(
            "\n\nHTTPS mode requires readable TLS cert/key files. "
            f"\n\nMissing cert={cert_path} key={key_path}. "
            "\n\nRun ./04_install_classifier_api_tls.sh to install TLS cert/key files."
        )
    return ("https", str(cert_path), str(key_path))


def main():
    # New files/dirs from this process: no group/other access (aligns with umask 007 in shell scripts).
    os.umask(0o007)
    #R001: Resolve bind host/port from environment with localhost defaults.
    host = os.environ.get("TELLER_CLASSIFIER_API_HOST", _DEFAULT_HOST).strip() or _DEFAULT_HOST
    port = int(os.environ.get("TELLER_CLASSIFIER_API_PORT", str(_DEFAULT_PORT)))
    if not _env_flag("TELLER_CLASSIFIER_ALLOW_NON_LOCAL_BIND", default=False) and not _is_local_bind_host(host):
        raise RuntimeError(
            f"Refusing non-local bind host '{host}'. "
            "Set TELLER_CLASSIFIER_ALLOW_NON_LOCAL_BIND=true for an explicit override."
        )
    scheme, certfile, keyfile = _resolve_transport()
    require_write_token()
    #R005: Launch uvicorn using teller classification ASGI app.
    uvicorn.run(create_app(), host=host, port=port, ssl_certfile=certfile, ssl_keyfile=keyfile)


if __name__ == "__main__":
    main()
