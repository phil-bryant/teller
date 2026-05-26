#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#R001: Install local TLS cert/key material for the classifier API defaults.
TLS_DIR="${TELLER_CLASSIFIER_TLS_DIR:-$HOME/.teller}"
TLS_CERT_FILE="${TELLER_CLASSIFIER_TLS_CERT_FILE:-$TLS_DIR/classifier-localhost-cert.pem}"
TLS_KEY_FILE="${TELLER_CLASSIFIER_TLS_KEY_FILE:-$TLS_DIR/classifier-localhost-key.pem}"
TLS_DAYS="${TELLER_CLASSIFIER_TLS_DAYS:-825}"

echo "▶ Installing local classifier API TLS materials"
echo "  cert: ${TLS_CERT_FILE}"
echo "  key : ${TLS_KEY_FILE}"

mkdir -p "$TLS_DIR"
chmod 700 "$TLS_DIR"

#R005: Keep existing valid-looking files to preserve local trust decisions.
if [[ -s "$TLS_CERT_FILE" && -s "$TLS_KEY_FILE" ]]; then
  echo "✅ TLS cert/key already present; no changes made."
  exit 0
fi

#R010: Prefer mkcert when available to produce locally-trusted certificates.
if command -v mkcert >/dev/null 2>&1; then
  mkcert -install >/dev/null 2>&1 || true
  mkcert -cert-file "$TLS_CERT_FILE" -key-file "$TLS_KEY_FILE" localhost 127.0.0.1 ::1
  chmod 600 "$TLS_CERT_FILE" "$TLS_KEY_FILE"
  echo "✅ Generated locally-trusted TLS cert/key via mkcert."
  exit 0
fi

#R015: Fallback to OpenSSL self-signed cert when mkcert is unavailable.
if ! command -v openssl >/dev/null 2>&1; then
  echo "❌ Neither mkcert nor openssl is available."
  echo "Install one and rerun this script."
  exit 1
fi

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -sha256 \
  -days "$TLS_DAYS" \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1" \
  -keyout "$TLS_KEY_FILE" \
  -out "$TLS_CERT_FILE" >/dev/null 2>&1

chmod 600 "$TLS_CERT_FILE" "$TLS_KEY_FILE"
echo "✅ Generated self-signed TLS cert/key via openssl."
echo "ℹ️  For trusted local certs, install mkcert and rerun this script."
