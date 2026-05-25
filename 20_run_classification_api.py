#! /usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

import uvicorn

REPO_ROOT = Path(__file__).resolve().parent
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from teller.teller_classification_api import create_app  # noqa: E402

_WRITE_TOKEN_PSA_ITEM = "TELLER_CLASSIFIER_WRITE_TOKEN"


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


def main():
    # New files/dirs from this process: no group/other access (aligns with umask 007 in shell scripts).
    os.umask(0o007)
    #R001: Resolve bind host/port from environment with localhost defaults.
    host = os.environ.get("TELLER_CLASSIFIER_API_HOST", "127.0.0.1")
    port = int(os.environ.get("TELLER_CLASSIFIER_API_PORT", "8787"))
    require_write_token()
    #R005: Launch uvicorn using teller classification ASGI app.
    uvicorn.run(create_app(), host=host, port=port)


if __name__ == "__main__":
    main()
