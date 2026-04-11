#!/bin/bash
umask 007

set -euo pipefail

TELLER_DIR="${HOME}/.teller"
AUTH_TOKEN_FILE="${TELLER_DIR}/auth_token.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_SERVER_SCRIPT="${SCRIPT_DIR}/teller_connect_token_server.py"
PORT="${PORT:-8080}"
CONNECT_ENVIRONMENT="${CONNECT_ENVIRONMENT:-development}"
CERT_FILE="${HOME}/.teller/certificate.pem"
KEY_FILE="${HOME}/.teller/private_key.pem"

usage() {
    echo "Usage:"
    echo "  ./06_capture_teller_token.sh                 # default: no copy/paste flow"
    echo "  ./06_capture_teller_token.sh --connect      # explicit no copy/paste flow"
    echo "  ./06_capture_teller_token.sh --manual"
    echo "  ./06_capture_teller_token.sh [token_xxx]"
    echo "  ./06_capture_teller_token.sh --clipboard"
    echo ""
    echo "No-copy mode starts a local Connect server on localhost:${PORT}."
}

validate_token() {
    local token="$1"
    if [ -z "$token" ]; then
        echo "❌ Access token is empty."
        exit 1
    fi
    if [[ "$token" != token_* ]]; then
        echo "⚠️  Token does not start with 'token_'. Continuing anyway."
    fi
}

get_token_from_clipboard() {
    if ! command -v pbpaste >/dev/null 2>&1; then
        echo "❌ pbpaste is not available; cannot read clipboard."
        exit 1
    fi
    pbpaste
}

verify_accounts_access() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "⚠️  curl not found; skipping /accounts verification."
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "⚠️  jq not found; skipping /accounts verification."
        return
    fi
    if [ ! -s "$CERT_FILE" ] || [ ! -s "$KEY_FILE" ]; then
        echo "⚠️  Missing Teller cert/key; skipping /accounts verification."
        return
    fi
    if [ ! -s "$AUTH_TOKEN_FILE" ]; then
        echo "⚠️  Missing ${AUTH_TOKEN_FILE}; skipping /accounts verification."
        return
    fi

    local token
    token="$(jq -r '.current // empty' "$AUTH_TOKEN_FILE")"
    if [ -z "$token" ]; then
        echo "⚠️  ${AUTH_TOKEN_FILE} does not contain .current; skipping /accounts verification."
        return
    fi

    echo "Checking Teller /accounts access with current token..."
    local response_file status
    response_file="$(mktemp)"
    status="$(curl -sS -o "$response_file" -w "%{http_code}" \
        --cert "$CERT_FILE" --key "$KEY_FILE" -u "${token}:" https://api.teller.io/accounts)"

    if [ "$status" = "200" ]; then
        echo "✅ /accounts verification passed."
    else
        echo "⚠️  /accounts verification returned HTTP ${status}."
        echo "Response:"
        cat "$response_file"
    fi

    rm -f "$response_file"
}

main() {
    local mode="${1:-}"
    local token=""

    case "$mode" in
        -h|--help)
            usage
            exit 0
            ;;
        ""|--connect)
            if [ ! -x "$CAPTURE_SERVER_SCRIPT" ]; then
                echo "❌ Missing executable capture server: $CAPTURE_SERVER_SCRIPT"
                echo "Try: chmod +x \"$CAPTURE_SERVER_SCRIPT\""
                exit 1
            fi
            PORT="$PORT" CONNECT_ENVIRONMENT="$CONNECT_ENVIRONMENT" "$CAPTURE_SERVER_SCRIPT" --port "$PORT" --environment "$CONNECT_ENVIRONMENT"
            verify_accounts_access
            exit 0
            ;;
        --manual)
            read -r -s -p "Paste Teller access token: " token
            echo ""
            ;;
        --clipboard)
            token="$(get_token_from_clipboard)"
            ;;
        *)
            token="$mode"
            ;;
    esac

    validate_token "$token"

    mkdir -p "$TELLER_DIR"
    chmod 700 "$TELLER_DIR"

    printf '{"current":"%s"}\n' "$token" > "$AUTH_TOKEN_FILE"
    chmod 400 "$AUTH_TOKEN_FILE"

    echo "✅ Saved Teller access token to ${AUTH_TOKEN_FILE}"
    verify_accounts_access
}

main "$@"
