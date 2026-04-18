#!/bin/bash
umask 007

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELLER_DIR="${HOME}/.teller"
APP_ID_FILE="${TELLER_DIR}/application_id.txt"
CERT_FILE="${TELLER_DIR}/certificate.pem"
KEY_FILE="${TELLER_DIR}/private_key.pem"
AUTH_TOKEN_FILE="${TELLER_DIR}/auth_token.json"
EXAMPLES_REPO_URL="${EXAMPLES_REPO_URL:-https://github.com/tellerhq/examples.git}"
TELLER_EXAMPLES_DIR="${TELLER_EXAMPLES_DIR:-${SCRIPT_DIR}/teller-connect-ui}"
CONFIGURE_TELLER_EXAMPLES="${CONFIGURE_TELLER_EXAMPLES:-true}"

TELLER_APP_PSA_ITEM="${TELLER_APP_PSA_ITEM:-}"
TELLER_APP_PSA_FIELD="${TELLER_APP_PSA_FIELD:-application_id}"
TELLER_CERT_PSA_ITEM="${TELLER_CERT_PSA_ITEM:-}"
TELLER_CERT_PSA_FIELD="${TELLER_CERT_PSA_FIELD:-certificate_pem}"
TELLER_KEY_PSA_ITEM="${TELLER_KEY_PSA_ITEM:-}"
TELLER_KEY_PSA_FIELD="${TELLER_KEY_PSA_FIELD:-private_key_pem}"
TELLER_AUTH_PSA_ITEM="${TELLER_AUTH_PSA_ITEM:-}"
TELLER_AUTH_PSA_FIELD="${TELLER_AUTH_PSA_FIELD:-access_token}"

status() {
    echo "[$1] $2"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Required command not found: $1"
        exit 1
    fi
}

read_1psa_field() {
    local item="$1"
    local field="$2"
    1psa -f "$item" "$field"
}

ensure_teller_dir() {
    mkdir -p "$TELLER_DIR"
    chmod 700 "$TELLER_DIR"
}

ensure_examples_repo() {
    status "teller-connect-ui" "Checking..."

    if [ "${CONFIGURE_TELLER_EXAMPLES}" != "true" ]; then
        status "teller-connect-ui" "Skipped (CONFIGURE_TELLER_EXAMPLES=${CONFIGURE_TELLER_EXAMPLES})"
        return
    fi

    if [ -d "${TELLER_EXAMPLES_DIR}/.git" ]; then
        status "teller-connect-ui" "Found existing repo at ${TELLER_EXAMPLES_DIR}"
        return
    fi

    if [ -e "${TELLER_EXAMPLES_DIR}" ]; then
        echo "❌ ${TELLER_EXAMPLES_DIR} exists but is not a git repository."
        echo "Move/remove it or set TELLER_EXAMPLES_DIR to a different path."
        exit 1
    fi

    status "teller-connect-ui" "Cloning Teller examples into ${TELLER_EXAMPLES_DIR}..."
    git clone "$EXAMPLES_REPO_URL" "$TELLER_EXAMPLES_DIR"
    status "teller-connect-ui" "Cloned"
}

write_secret_file() {
    local path="$1"
    local value="$2"
    printf "%s" "$value" > "$path"
    chmod 400 "$path"
}

ensure_application_id() {
    status "application_id" "Checking..."

    if [ -s "$APP_ID_FILE" ]; then
        status "application_id" "Found existing ${APP_ID_FILE}"
        return
    fi

    if [ -n "${TELLER_APPLICATION_ID:-}" ]; then
        write_secret_file "$APP_ID_FILE" "$TELLER_APPLICATION_ID"
        status "application_id" "Wrote ${APP_ID_FILE} from TELLER_APPLICATION_ID"
        return
    fi

    if [ -n "$TELLER_APP_PSA_ITEM" ]; then
        require_command "1psa"
        write_secret_file "$APP_ID_FILE" "$(read_1psa_field "$TELLER_APP_PSA_ITEM" "$TELLER_APP_PSA_FIELD")"
        status "application_id" "Wrote ${APP_ID_FILE} from 1psa item ${TELLER_APP_PSA_ITEM}"
        return
    fi

    echo "❌ Missing application id."
    echo "Set TELLER_APPLICATION_ID or provide TELLER_APP_PSA_ITEM/TELLER_APP_PSA_FIELD."
    exit 1
}

ensure_cert_and_key() {
    status "certificates" "Checking..."

    if [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]; then
        chmod 400 "$CERT_FILE" "$KEY_FILE"
        status "certificates" "Found existing certificate and private key"
        return
    fi

    if [ -n "${TELLER_CERT_PATH:-}" ] && [ -n "${TELLER_KEY_PATH:-}" ]; then
        if [ ! -s "$TELLER_CERT_PATH" ] || [ ! -s "$TELLER_KEY_PATH" ]; then
            echo "❌ TELLER_CERT_PATH or TELLER_KEY_PATH points to a missing/empty file."
            exit 1
        fi
        cp "$TELLER_CERT_PATH" "$CERT_FILE"
        cp "$TELLER_KEY_PATH" "$KEY_FILE"
        chmod 400 "$CERT_FILE" "$KEY_FILE"
        status "certificates" "Copied cert/key from TELLER_CERT_PATH and TELLER_KEY_PATH"
        return
    fi

    if [ -n "$TELLER_CERT_PSA_ITEM" ] && [ -n "$TELLER_KEY_PSA_ITEM" ]; then
        require_command "1psa"
        write_secret_file "$CERT_FILE" "$(read_1psa_field "$TELLER_CERT_PSA_ITEM" "$TELLER_CERT_PSA_FIELD")"
        write_secret_file "$KEY_FILE" "$(read_1psa_field "$TELLER_KEY_PSA_ITEM" "$TELLER_KEY_PSA_FIELD")"
        status "certificates" "Wrote cert/key from 1psa items"
        return
    fi

    echo "❌ Missing Teller certificate/private key."
    echo "Provide TELLER_CERT_PATH and TELLER_KEY_PATH, or TELLER_CERT_PSA_ITEM and TELLER_KEY_PSA_ITEM."
    exit 1
}

ensure_auth_token_if_provided() {
    status "auth_token" "Checking..."

    if [ -s "$AUTH_TOKEN_FILE" ]; then
        status "auth_token" "Found existing ${AUTH_TOKEN_FILE}"
        return
    fi

    if [ -n "${TELLER_ACCESS_TOKEN:-}" ]; then
        printf '{"current":"%s"}\n' "$TELLER_ACCESS_TOKEN" > "$AUTH_TOKEN_FILE"
        chmod 400 "$AUTH_TOKEN_FILE"
        status "auth_token" "Wrote ${AUTH_TOKEN_FILE} from TELLER_ACCESS_TOKEN"
        return
    fi

    if [ -n "$TELLER_AUTH_PSA_ITEM" ]; then
        require_command "1psa"
        local token
        token="$(read_1psa_field "$TELLER_AUTH_PSA_ITEM" "$TELLER_AUTH_PSA_FIELD")"
        printf '{"current":"%s"}\n' "$token" > "$AUTH_TOKEN_FILE"
        chmod 400 "$AUTH_TOKEN_FILE"
        status "auth_token" "Wrote ${AUTH_TOKEN_FILE} from 1psa item ${TELLER_AUTH_PSA_ITEM}"
        return
    fi

    status "auth_token" "Not configured (manual Teller Connect enrollment still required)"
}

smoke_test_teller_api() {
    local app_id
    app_id="$(tr -d '\r\n' < "$APP_ID_FILE")"
    if [ -z "$app_id" ]; then
        echo "❌ application_id.txt is empty."
        exit 1
    fi
    if [[ ! "$app_id" =~ ^app_ ]]; then
        status "smoke" "Warning: application_id does not start with app_"
    fi

    require_command "curl"
    require_command "jq"

    status "smoke" "Testing /institutions endpoint with mTLS..."
    local institutions_status
    institutions_status="$(curl -sS -o /tmp/teller_institutions.json -w "%{http_code}" \
        --cert "$CERT_FILE" --key "$KEY_FILE" https://api.teller.io/institutions)"

    if [ "$institutions_status" != "200" ]; then
        echo "❌ Teller /institutions check failed with HTTP ${institutions_status}"
        echo "Response:"
        cat /tmp/teller_institutions.json
        exit 1
    fi
    local institutions_count
    institutions_count="$(jq 'length' /tmp/teller_institutions.json 2>/dev/null || echo "unknown")"
    status "smoke" "Institutions check passed (count: ${institutions_count})"

    if [ -s "$AUTH_TOKEN_FILE" ]; then
        status "smoke" "Testing /accounts endpoint with access token..."
        local token
        token="$(jq -r '.current // empty' "$AUTH_TOKEN_FILE")"
        if [ -z "$token" ]; then
            echo "❌ ${AUTH_TOKEN_FILE} exists but .current is missing/empty."
            exit 1
        fi

        local accounts_status
        accounts_status="$(curl -sS -o /tmp/teller_accounts.json -w "%{http_code}" \
            --cert "$CERT_FILE" --key "$KEY_FILE" -u "${token}:" https://api.teller.io/accounts)"

        if [ "$accounts_status" = "200" ]; then
            status "smoke" "Accounts check passed"
        else
            status "smoke" "Accounts check returned HTTP ${accounts_status}"
            status "smoke" "If token is stale, reconnect with Teller Connect and update auth_token.json"
        fi
    fi
}

main() {
    echo "============================================================"
    echo "Teller.io Configuration"
    echo "============================================================"
    echo ""

    ensure_teller_dir
    ensure_examples_repo
    ensure_application_id
    ensure_cert_and_key
    ensure_auth_token_if_provided
    smoke_test_teller_api

    echo ""
    echo "✅ Teller configuration is ready."
    echo "Teller examples repo: ${TELLER_EXAMPLES_DIR}"
    echo "Files in ${TELLER_DIR}:"
    echo "- application_id.txt"
    echo "- certificate.pem"
    echo "- private_key.pem"
    if [ -s "$AUTH_TOKEN_FILE" ]; then
        echo "- auth_token.json"
    else
        echo "- auth_token.json (not present; create via Teller Connect if needed)"
    fi
}

main "$@"
