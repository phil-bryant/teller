#!/bin/bash
umask 007

set -euo pipefail

TELLER_DIR="${HOME}/.teller"
AUTH_TOKEN_FILE="${TELLER_DIR}/auth_token.json"
ENROLLMENT_ID_FILE="${TELLER_DIR}/enrollment_id.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_SERVER_SCRIPT="${SCRIPT_DIR}/teller_connect_token_server.py"
PORT="${PORT:-8080}"
CONNECT_ENVIRONMENT="${CONNECT_ENVIRONMENT:-development}"
ENROLLMENT_ID="${ENROLLMENT_ID:-}"
AUTO_REPAIR="${AUTO_REPAIR:-true}"
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
    echo "Set ENROLLMENT_ID to run Teller Connect repair mode (no new enrollment)."
    echo "If AUTO_REPAIR=true and ~/.teller/enrollment_id.txt exists, repair mode is automatic."
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

write_auth_token_file() {
    local token="$1"
    mkdir -p "$TELLER_DIR"
    chmod 700 "$TELLER_DIR"

    local tmp_file
    tmp_file="$(mktemp "${TELLER_DIR}/auth_token.XXXXXX.json")"
    printf '{"current":"%s"}\n' "$token" > "$tmp_file"
    chmod 400 "$tmp_file"
    mv "$tmp_file" "$AUTH_TOKEN_FILE"
}

resolve_enrollment_id() {
    if [ -n "$ENROLLMENT_ID" ]; then
        return
    fi
    if [ "$AUTO_REPAIR" = "true" ] && [ -s "$ENROLLMENT_ID_FILE" ]; then
        ENROLLMENT_ID="$(tr -d '\r\n' < "$ENROLLMENT_ID_FILE")"
    fi
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
        local error_code
        error_code="$(jq -r '.error.code // empty' "$response_file" 2>/dev/null || echo "")"
        if [ -n "$error_code" ]; then
            echo "Teller error code: ${error_code}"
        fi
        if [[ "$error_code" == enrollment.disconnected* ]] && [ -z "$ENROLLMENT_ID" ]; then
            echo "Use repair mode with your existing enrollment id (no re-enrollment):"
            echo "  ENROLLMENT_ID=enr_xxx ./06_capture_teller_token.sh"
        fi
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
            resolve_enrollment_id
            if [ -n "$ENROLLMENT_ID" ]; then
                echo "Using repair mode for enrollment: ${ENROLLMENT_ID}"
            fi
            PORT="$PORT" CONNECT_ENVIRONMENT="$CONNECT_ENVIRONMENT" ENROLLMENT_ID="$ENROLLMENT_ID" \
                "$CAPTURE_SERVER_SCRIPT" --port "$PORT" --environment "$CONNECT_ENVIRONMENT" --enrollment-id "$ENROLLMENT_ID"
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

    write_auth_token_file "$token"

    echo "✅ Saved Teller access token to ${AUTH_TOKEN_FILE}"
    verify_accounts_access
}

main "$@"
