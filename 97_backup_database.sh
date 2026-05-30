#!/usr/bin/env bash
#R001: Enforce strict shell mode and secure default file permissions.
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
#R040: Resolve the active DB profile so backups target the same database as deploy/destroy.
DB_PROFILE_HELPER="${SCRIPT_DIR}/src/scripts/db_profile_export.sh"
BACKUP_INCLUDE_ROLE_AUTH_DATA="${BACKUP_INCLUDE_ROLE_AUTH_DATA:-false}"
MANIFEST_PATH=""

#R005: Require backup dependencies before running dump commands.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

#R005: Require pg_dump.
if ! command -v pg_dump >/dev/null 2>&1; then
    echo "pg_dump is required but was not found on PATH."
    exit 1
fi

#R005: Require pg_dumpall.
if ! command -v pg_dumpall >/dev/null 2>&1; then
    echo "pg_dumpall is required but was not found on PATH."
    exit 1
fi

#R040: Refuse backup when the profile helper is missing so we never silently fall back
#R040: to a stale hard-coded target.
if [[ ! -x "$DB_PROFILE_HELPER" ]]; then
    echo "DB profile helper is missing or not executable: ${DB_PROFILE_HELPER}"
    exit 1
fi

#R040: Whitelist the profile export keys so we cannot accidentally source arbitrary env.
load_profile_exports_from_file() {
    local exports_file="$1"
    local invalid_lines=""
    invalid_lines="$(awk '
        !/^(export )?[A-Za-z_][A-Za-z0-9_]*=.*/ { print; next }
        {
            key=$0
            sub(/^export[[:space:]]+/, "", key)
            sub(/=.*/, "", key)
            if (key !~ /^(DB_DIALECT|PROFILE_NAME|PROFILE_TARGET|PG_HOST|PG_PORT|PG_DBNAME|PG_USER|PG_SSLMODE|PG_SEARCH_PATH|PG_RUNTIME_ROLE|PG_ONEPSA_ITEM|SQLITE_PATH)$/) {
                print
            }
        }
    ' "$exports_file")"
    if [[ -n "$invalid_lines" ]]; then
        echo "Refusing to load unexpected profile export lines:"
        printf '%s\n' "$invalid_lines"
        return 1
    fi
    set -a
    # shellcheck disable=SC1090
    source "$exports_file"
    set +a
}

require_nonempty_env() {
    local scope="$1"
    shift
    local var_name
    for var_name in "$@"; do
        if [[ -z "${!var_name:-}" ]]; then
            echo "${scope} requires non-empty ${var_name}; check config/db-profiles.json or the profile 1psa item."
            exit 1
        fi
    done
}

profile_exports_file="$(mktemp)"
if ! "$DB_PROFILE_HELPER" >"$profile_exports_file"; then
    rm -f "$profile_exports_file"
    exit 1
fi
if ! load_profile_exports_from_file "$profile_exports_file"; then
    rm -f "$profile_exports_file"
    exit 1
fi
rm -f "$profile_exports_file"
require_nonempty_env "Profile resolution" PROFILE_NAME PROFILE_TARGET
DB_DIALECT="${DB_DIALECT:-postgresql}"
if [[ "$DB_DIALECT" != "sqlite" && "${PROFILE_TARGET:-local}" != "sqlite" ]]; then
    require_nonempty_env "Profile resolution" PG_DBNAME
fi

#R020: Create backup directory with restricted permissions.
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

#R041: Support SQLite backups through the existing backup entrypoint.
if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
    SQLITE_DB_PATH="${SQLITE_PATH:-}"
    if [[ -z "$SQLITE_DB_PATH" ]]; then
        echo "SQLite backup requires SQLITE_PATH from db profile export."
        exit 1
    fi
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "SQLite database file does not exist: $SQLITE_DB_PATH"
        exit 1
    fi
    SQLITE_DB_BASENAME="$(basename "$SQLITE_DB_PATH" .sqlite3)"
    BACKUP_BASENAME="${PROFILE_NAME}_${SQLITE_DB_BASENAME}_${TIMESTAMP}"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}.dump"
    cp "$SQLITE_DB_PATH" "$BACKUP_PATH"
    chmod 600 "$BACKUP_PATH"
    echo "Backup written: $BACKUP_PATH"
    exit 0
fi

#R045: Managed-target backup uses the profile's connection user and the direct (non-pooler) host.
if [[ "${PROFILE_TARGET:-local}" == "managed" ]]; then
    if [[ "$PROFILE_NAME" != "supabase_direct" && -x "$DB_PROFILE_HELPER" ]]; then
        profile_exports_file="$(mktemp)"
        if ! "$DB_PROFILE_HELPER" --profile supabase_direct >"$profile_exports_file"; then
            rm -f "$profile_exports_file"
            exit 1
        fi
        if ! load_profile_exports_from_file "$profile_exports_file"; then
            rm -f "$profile_exports_file"
            exit 1
        fi
        rm -f "$profile_exports_file"
    fi
    require_nonempty_env "Managed direct backup profile" PROFILE_NAME PG_HOST PG_PORT PG_DBNAME PG_USER PG_SEARCH_PATH

    #R045: Resolve managed-target password from the profile's 1psa item; env var still wins.
    MANAGED_PASSWORD="${TELLER_DB_PASSWORD:-}"
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        if [[ -z "${PG_ONEPSA_ITEM:-}" ]]; then
            echo "Managed backup requires PG_ONEPSA_ITEM (from config/db-profiles.json) or TELLER_DB_PASSWORD."
            exit 1
        fi
        MANAGED_PASSWORD="$(1psa -p "$PG_ONEPSA_ITEM")"
    fi
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        echo "Failed to read managed DB password (item: ${PG_ONEPSA_ITEM:-<unset>})"
        exit 1
    fi

    #R025: Write timestamped custom-format schema-scoped database dump.
    BACKUP_BASENAME="${PROFILE_NAME}_${PG_DBNAME}_${TIMESTAMP}"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}.dump"
    echo "ℹ️  Backing up managed schema via profile=${PROFILE_NAME} host=${PG_HOST} port=${PG_PORT} db=${PG_DBNAME} user=${PG_USER} schema=${PG_SEARCH_PATH}"
    PGPASSWORD="$MANAGED_PASSWORD" PGSSLMODE="$PG_SSLMODE" pg_dump \
        -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DBNAME" \
        -Fc -n "$PG_SEARCH_PATH" -f "$BACKUP_PATH"

    #R045: Managed targets do not expose pg_authid; skip pg_dumpall and document the gap.
    #R035: Restrict output file permissions and print resulting paths.
    chmod 600 "$BACKUP_PATH"
    echo "Backup written: $BACKUP_PATH"
    echo "Globals skipped: managed target does not expose role/grant state; restore is --table scoped only."
    exit 0
fi

#R010: Local target uses configurable postgres admin via 1psa.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
#R050: Honor DATABASE_NAME env override for backward compatibility, otherwise use the resolved profile DB.
DATABASE_NAME="${DATABASE_NAME:-$PG_DBNAME}"
BACKUP_BASENAME="${PROFILE_NAME}_${DATABASE_NAME}_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}.dump"
GLOBALS_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}_globals.sql"
MANIFEST_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}.manifest.sha256"

#R010: Resolve postgres password from configured 1psa item/field.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

#R015: Refuse backup when password lookup is empty.
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

echo "ℹ️  Backing up local database via profile=${PROFILE_NAME} db=${DATABASE_NAME}"

#R025: Write timestamped custom-format database dump.
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d "$DATABASE_NAME" -Fc -C -f "$BACKUP_PATH"
#R030: Write matching globals-only dump for roles/grants.
GLOBALS_ROLE_PASSWORD_ARGS=()
if [ "$BACKUP_INCLUDE_ROLE_AUTH_DATA" != "true" ]; then
    GLOBALS_ROLE_PASSWORD_ARGS+=(--no-role-passwords)
fi
PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres --globals-only "${GLOBALS_ROLE_PASSWORD_ARGS[@]}" -f "$GLOBALS_BACKUP_PATH"

#R035: Restrict output file permissions and print resulting paths.
chmod 600 "$BACKUP_PATH"
chmod 600 "$GLOBALS_BACKUP_PATH"
#R055: Generate and lock down SHA-256 manifest for dump/globals integrity verification.
(
    cd "$BACKUP_DIR" && \
    shasum -a 256 "$(basename "$BACKUP_PATH")" "$(basename "$GLOBALS_BACKUP_PATH")" > "$(basename "$MANIFEST_PATH")"
)
chmod 600 "$MANIFEST_PATH"
echo "Backup written: $BACKUP_PATH"
echo "Globals written: $GLOBALS_BACKUP_PATH"
echo "Manifest written: $MANIFEST_PATH"
