#! /usr/bin/env python3
import os
import uvicorn
from teller.teller_classification_api import create_app


def main():
    # New files/dirs from this process: no group/other access (aligns with umask 007 in shell scripts).
    os.umask(0o007)
    #R001: Resolve bind host/port from environment with localhost defaults.
    host = os.environ.get("TELLER_CLASSIFIER_API_HOST", "127.0.0.1")
    port = int(os.environ.get("TELLER_CLASSIFIER_API_PORT", "8787"))
    #R005: Launch uvicorn using teller classification ASGI app.
    uvicorn.run(create_app(), host=host, port=port)


if __name__ == "__main__":
    main()
