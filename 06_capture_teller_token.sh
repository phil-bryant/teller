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
CERT_FILE="${HOME}/.teller/certificate.pem"
KEY_FILE="${HOME}/.teller/private_key.pem"
SELECTOR_INSTITUTION_ID=""
SELECTOR_ENROLLMENT_ID=""
CONFIRM_DELETE="false"
RESOLVED_CONTEXT=""
DEBUG_LOG_PATH="/Users/phil/local/src/teller/.cursor/debug-581bea.log"
DEBUG_SESSION_ID="581bea"
DEBUG_RUN_ID="pre-fix"

debug_json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    echo "$value"
}

debug_log() {
    local hypothesis_id="$1" location="$2" message="$3" detail="$4" ts detail_escaped
    ts="$(( $(date +%s) * 1000 ))"
    detail_escaped="$(debug_json_escape "$detail")"
    printf '{"sessionId":"%s","runId":"%s","hypothesisId":"%s","location":"%s","message":"%s","data":{"detail":"%s"},"timestamp":%s}\n' \
        "$DEBUG_SESSION_ID" "$DEBUG_RUN_ID" "$hypothesis_id" "$location" "$message" "$detail_escaped" "$ts" >> "$DEBUG_LOG_PATH"
}

print_context_row() {
    #R055: Produce one normalized context row for list output.
    local source="$1" institution_id="$2" enrollment_id="$3" token_path="$4" enrollment_path="$5"
    local display_institution="$institution_id" display_enrollment="$enrollment_id"
    [ -n "$display_institution" ] || display_institution="<default>"
    [ -n "$display_enrollment" ] || display_enrollment="<missing>"
    printf "%s|%s|%s|%s|%s\n" "$source" "$display_institution" "$display_enrollment" "$token_path" "$enrollment_path"
}

token_from_file() {
    local path="$1"
    if [ ! -s "$path" ]; then
        echo ""
        return
    fi
    if command -v jq >/dev/null 2>&1; then
        jq -r '.current // empty' "$path"
        return
    fi
    sed -n 's/.*"current"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$path" | sed -n '1p'
}

collect_context_rows() {
    #R055: Discover default and suffixed enrollment contexts.
    local token enrollment suffix token_file enrollment_file
    if [ -f "$AUTH_TOKEN_FILE" ] || [ -f "$ENROLLMENT_ID_FILE" ]; then
        token="$(token_from_file "$AUTH_TOKEN_FILE")"
        enrollment=""
        [ -s "$ENROLLMENT_ID_FILE" ] && enrollment="$(tr -d '\r\n' < "$ENROLLMENT_ID_FILE")"
        print_context_row "default" "" "$enrollment" "$AUTH_TOKEN_FILE" "$ENROLLMENT_ID_FILE"
    fi
    for token_file in "$TELLER_DIR"/auth_token_*.json; do
        [ -e "$token_file" ] || continue
        suffix="${token_file##*/auth_token_}"
        suffix="${suffix%.json}"
        enrollment_file="${TELLER_DIR}/enrollment_id_${suffix}.txt"
        enrollment=""
        [ -s "$enrollment_file" ] && enrollment="$(tr -d '\r\n' < "$enrollment_file")"
        print_context_row "suffix" "$suffix" "$enrollment" "$token_file" "$enrollment_file"
    done
}

list_contexts() {
    #R055: List all discovered local enrollment contexts.
    local rows
    rows="$(collect_context_rows)"
    if [ -z "$rows" ]; then
        echo "No local enrollments found under ${TELLER_DIR}."
        return
    fi
    printf "%-10s %-28s %-36s %s\n" "source" "institution_id" "enrollment_id" "paths"
    echo "$rows" | while IFS='|' read -r source institution enrollment token_path enrollment_path; do
        printf "%-10s %-28s %-36s token=%s enrollment=%s\n" \
            "$source" "$institution" "$enrollment" "$token_path" "$enrollment_path"
    done
}

parse_selector_args() {
    #R085: Parse selector arguments for scoped context operations.
    while [ $# -gt 0 ]; do
        case "$1" in
            --institution_id|--institution-id)
                shift
                [ $# -gt 0 ] || { echo "❌ Missing value for --institution_id"; exit 1; }
                SELECTOR_INSTITUTION_ID="$1"
                ;;
            --enrollment_id|--enrollment-id)
                shift
                [ $# -gt 0 ] || { echo "❌ Missing value for --enrollment_id"; exit 1; }
                SELECTOR_ENROLLMENT_ID="$1"
                ;;
            --yes)
                CONFIRM_DELETE="true"
                ;;
            *)
                echo "❌ Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

resolve_single_context() {
    #R085: Resolve exactly one context; reject missing or ambiguous selectors.
    local rows matched line source institution enrollment token_path enrollment_path count
    rows="$(collect_context_rows)"
    [ -n "$rows" ] || { echo "❌ No local enrollment contexts found."; return 10; }
    [ -n "$SELECTOR_INSTITUTION_ID" ] || [ -n "$SELECTOR_ENROLLMENT_ID" ] || {
        echo "❌ Selector required: pass --institution_id and/or --enrollment_id."
        return 11
    }
    matched=""
    count=0
    while IFS='|' read -r source institution enrollment token_path enrollment_path; do
        [ -n "$source" ] || continue
        [ -n "$SELECTOR_INSTITUTION_ID" ] && [ "$institution" != "$SELECTOR_INSTITUTION_ID" ] && continue
        [ -n "$SELECTOR_ENROLLMENT_ID" ] && [ "$enrollment" != "$SELECTOR_ENROLLMENT_ID" ] && continue
        matched="$source|$institution|$enrollment|$token_path|$enrollment_path"
        count=$((count + 1))
    done <<EOF
$rows
EOF
    if [ "$count" -eq 0 ]; then
        echo "No enrollment context matched selector."
        list_contexts
        return 12
    fi
    if [ "$count" -gt 1 ]; then
        echo "❌ Selector is ambiguous; refine with both --institution_id and --enrollment_id."
        list_contexts
        return 13
    fi
    RESOLVED_CONTEXT="$matched"
    return 0
}

move_to_trash() {
    #R060: Delete mode must be reversible locally (Trash, not permanent delete).
    local path="$1"
    [ -e "$path" ] || return
    local trash_dir timestamp base dest
    trash_dir="${HOME}/.Trash/teller-enrollment-removals"
    mkdir -p "$trash_dir"
    timestamp="$(date +%Y-%m-%d-%H.%M.%S)"
    base="${path##*/}"
    dest="${trash_dir}/${base}.${timestamp}"
    mv "$path" "$dest"
    echo "Moved to trash: ${path} -> ${dest}"
}

run_connect_capture() {
    #R065 #R070: Reconnect and add share capture flow with caller-selected outputs.
    local repair_enrollment_id="$1" output_token_file="$2" output_enrollment_file="$3" capture_mode="${4:-capture}"
    if [ ! -x "$CAPTURE_SERVER_SCRIPT" ]; then
        echo "❌ Missing executable capture server: $CAPTURE_SERVER_SCRIPT"
        echo "Try: chmod +x \"$CAPTURE_SERVER_SCRIPT\""
        exit 1
    fi
    [ -n "$repair_enrollment_id" ] && echo "Using repair mode for enrollment: ${repair_enrollment_id}"
    PORT="$PORT" CONNECT_ENVIRONMENT="$CONNECT_ENVIRONMENT" ENROLLMENT_ID="$repair_enrollment_id" \
        AUTH_TOKEN_OUTPUT_FILE="$output_token_file" ENROLLMENT_ID_OUTPUT_FILE="$output_enrollment_file" \
        "$CAPTURE_SERVER_SCRIPT" --port "$PORT" --environment "$CONNECT_ENVIRONMENT" \
        --enrollment-id "$repair_enrollment_id" --auth-token-file "$output_token_file" \
        --enrollment-id-file "$output_enrollment_file" --mode "$capture_mode"
}

sanitize_suffix() {
    local raw="$1"
    raw="$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]')"
    raw="$(printf "%s" "$raw" | tr -c 'a-z0-9_' '_')"
    raw="${raw##_}"
    raw="${raw%%_}"
    [ -n "$raw" ] || raw="enrollment"
    echo "$raw"
}

infer_institution_id_from_token_file() {
    local token_file="$1" token response_file status institution_id
    [ -s "$token_file" ] || { echo ""; return; }
    [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ] || { echo ""; return; }
    token="$(token_from_file "$token_file")"
    [ -n "$token" ] || { echo ""; return; }
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo ""
        return
    fi
    response_file="$(mktemp)"
    status="$(curl -sS -o "$response_file" -w "%{http_code}" \
        --cert "$CERT_FILE" --key "$KEY_FILE" -u "${token}:" https://api.teller.io/identity)"
    if [ "$status" = "200" ]; then institution_id="$(jq -r '.[0].account.institution.id // empty' "$response_file")"; else institution_id=""; fi
    rm -f "$response_file"
    echo "$institution_id"
}

ensure_unique_suffix() {
    #region agent log
    debug_log "H1" "06_capture_teller_token.sh:ensure_unique_suffix" "entry" "raw_arg=$1"
    #endregion
    local base="$1" candidate="$base" i=1
    while [ -e "${TELLER_DIR}/auth_token_${candidate}.json" ] || [ -e "${TELLER_DIR}/enrollment_id_${candidate}.txt" ]; do
        candidate="${base}_${i}"
        i=$((i + 1))
    done
    echo "$candidate"
}

usage() {
    #R050 #R055 #R060 #R065 #R070: Document supported enrollment-management modes.
    echo "Usage:"
    echo "  ./06_capture_teller_token.sh                 # default: no copy/paste flow"
    echo "  ./06_capture_teller_token.sh --connect      # explicit no copy/paste flow"
    echo "  ./06_capture_teller_token.sh --manual"
    echo "  ./06_capture_teller_token.sh [token_xxx]"
    echo "  ./06_capture_teller_token.sh --clipboard"
    echo "  ./06_capture_teller_token.sh --list"
    echo "  ./06_capture_teller_token.sh --delete --institution_id <id>|--enrollment_id <id> [--yes]"
    echo "  ./06_capture_teller_token.sh --reconnect --institution_id <id>|--enrollment_id <id>"
    echo "  ./06_capture_teller_token.sh --add"
    echo ""
    echo "Default mode opens a local enrollment manager UI on localhost:${PORT}."
    echo "Use the page to reconnect, delete local contexts, or add an enrollment."
    echo "Set ENROLLMENT_ID to run Teller Connect repair mode (no new enrollment)."
}

validate_token() {
    #R075: Validate captured token before writing auth file.
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
    #R075: Support clipboard-based token ingestion.
    if ! command -v pbpaste >/dev/null 2>&1; then
        echo "❌ pbpaste is not available; cannot read clipboard."
        exit 1
    fi
    pbpaste
}

write_auth_token_file() {
    #R075 #R090: Write auth token atomically with restrictive permissions.
    local token="$1"
    mkdir -p "$TELLER_DIR"
    chmod 700 "$TELLER_DIR"

    local tmp_file
    tmp_file="$(mktemp "${TELLER_DIR}/auth_token.XXXXXX.json")"
    printf '{"current":"%s"}\n' "$token" > "$tmp_file"
    chmod 400 "$tmp_file"
    mv "$tmp_file" "$AUTH_TOKEN_FILE"
}

verify_accounts_access() {
    #R080: Run best-effort accounts verification with warning-only skip paths.
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
    local token="" selected source institution enrollment token_path enrollment_path token_out enrollment_out
    [ $# -gt 0 ] && shift

    case "$mode" in
        -h|--help)
            usage
            exit 0
            ;;
        ""|--connect)
            #R050: Default/connect mode launches local enrollment manager.
            run_connect_capture "" "$AUTH_TOKEN_FILE" "$ENROLLMENT_ID_FILE" "manage"
            exit 0
            ;;
        --list)
            #R055: Enrollment-management list action.
            list_contexts
            exit 0
            ;;
        --delete)
            #R060 #R085: Delete selected enrollment context only.
            parse_selector_args "$@"
            resolve_single_context || {
                case "$?" in
                    12|13) exit 0 ;;
                    *) exit 1 ;;
                esac
            }
            selected="$RESOLVED_CONTEXT"
            IFS='|' read -r source institution enrollment token_path enrollment_path <<EOF
$selected
EOF
            echo "Delete enrollment context:"
            echo "  source=${source} institution_id=${institution} enrollment_id=${enrollment}"
            echo "  token=${token_path}"
            echo "  enrollment=${enrollment_path}"
            if [ "$CONFIRM_DELETE" != "true" ]; then
                local answer
                read -r -p "Type 'delete' to confirm: " answer
                [ "$answer" = "delete" ] || { echo "Delete cancelled."; exit 0; }
            fi
            move_to_trash "$token_path"
            move_to_trash "$enrollment_path"
            echo "✅ Deleted local enrollment context."
            exit 0
            ;;
        --reconnect)
            #R065 #R085: Reconnect selected enrollment via repair mode.
            parse_selector_args "$@"
            resolve_single_context || exit 1
            selected="$RESOLVED_CONTEXT"
            IFS='|' read -r source institution enrollment token_path enrollment_path <<EOF
$selected
EOF
            [ "$enrollment" != "<missing>" ] || { echo "❌ Selected context has no enrollment_id to reconnect."; exit 1; }
            [ "$enrollment" != "" ] || { echo "❌ Selected context has no enrollment_id to reconnect."; exit 1; }
            run_connect_capture "$enrollment" "$token_path" "$enrollment_path" "capture"
            echo "✅ Reconnected selected enrollment context."
            verify_accounts_access
            exit 0
            ;;
        --add)
            #R070 #R090: Add new enrollment without touching existing contexts.
            [ $# -eq 0 ] || { echo "❌ --add takes no selector args; choose institution in Teller Connect UI."; exit 1; }
            mkdir -p "$TELLER_DIR"
            token_out="$(mktemp "${TELLER_DIR}/auth_token.add.XXXXXX.json")"
            enrollment_out="$(mktemp "${TELLER_DIR}/enrollment_id.add.XXXXXX.txt")"
            chmod 400 "$token_out" "$enrollment_out"
            #region agent log
            debug_log "H2" "06_capture_teller_token.sh:main:add" "temp_output_paths" "token_out=$token_out enrollment_out=$enrollment_out"
            #endregion
            run_connect_capture "" "$token_out" "$enrollment_out" "capture"
            institution="$(infer_institution_id_from_token_file "$token_out")"
            #region agent log
            debug_log "H3" "06_capture_teller_token.sh:main:add" "institution_from_identity" "institution=$institution"
            #endregion
            [ -n "$institution" ] || institution="$(tr -d '\r\n' < "$enrollment_out")"
            #region agent log
            debug_log "H4" "06_capture_teller_token.sh:main:add" "institution_after_fallback" "institution=$institution"
            #endregion
            institution="$(sanitize_suffix "$institution")"
            #region agent log
            debug_log "H5" "06_capture_teller_token.sh:main:add" "institution_after_sanitize" "institution=$institution"
            #endregion
            institution="$(ensure_unique_suffix "$institution")"
            token_path="${TELLER_DIR}/auth_token_${institution}.json"
            enrollment_path="${TELLER_DIR}/enrollment_id_${institution}.txt"
            mv "$token_out" "$token_path"
            mv "$enrollment_out" "$enrollment_path"
            echo "✅ Added enrollment context (selected in Connect UI)."
            echo "  institution_id=${institution}"
            echo "  token=${token_path}"
            echo "  enrollment=${enrollment_path}"
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
