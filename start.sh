#!/bin/bash
# Do Not use uvicorn directly - activate venv first
source teller-venv/bin/activate

# Generate self-signed cert if it does not exist
if [ ! -f localhost.pem ] || [ ! -f localhost.key ]; then
    openssl req -x509 -newkey rsa:4096 -nodes -keyout localhost.key -out localhost.pem -days 365 -subj "/CN=localhost"
fi

# Run with SSL - use absolute path for reload-exclude
python -m uvicorn main:app --reload --reload-exclude "${HOME}/.teller" --ssl-keyfile=localhost.key --ssl-certfile=localhost.pem --host 0.0.0.0 --port 8443 