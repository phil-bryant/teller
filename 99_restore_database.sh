#!/usr/bin/env bash
#R001: Enforce strict shell mode and secure default file permissions.
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
#R085: Resolve the active DB profile via the shared helper so restore targets the same database as deploy/destroy.
DB_PROFILE_HELPER="${SCRIPT_DIR}/src/scripts/db_profile_export.sh"
BACKUP_ENCRYPTION_ITEM="${BACKUP_ENCRYPTION_ITEM:-POSTGRES_BACKUP_ENCRYPTION}"

BACKUP_PATH=""
GLOBALS_BACKUP_PATH=""
TABLE_NAME=""
TABLE_SCHEMA=""
TABLE_RELATION=""
MANIFEST_PATH=""
BACKUP_INPUT_PATH=""
GLOBALS_RESTORE_PATH=""
GPG_HOME=""

cleanup_paths=()
cleanup() {
    local path=""
    for path in "${cleanup_paths[@]:-}"; do
        if [[ -d "$path" ]]; then
            rm -rf "$path"
        elif [[ -n "$path" ]]; then
            rm -f "$path"
        fi
    done
}
trap cleanup EXIT

usage() {
    echo "Usage: $0 [--from /path/to/backup.dump.gpg] [--table table_name|schema.table_name]"
}

is_valid_pg_identifier() {
    local identifier="$1"
    [[ "$identifier" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]
}

verify_backup_manifest() {
    local backup_path="$1"
    local globals_path="$2"
    local manifest_path="$3"
    local manifest_dir=""
    manifest_dir="$(dirname "$manifest_path")"

    if [ ! -f "$manifest_path" ]; then
        echo "Backup integrity manifest is missing: $manifest_path"
        echo "Recreate backup with 97_backup_database.sh to include signed hash metadata."
        exit 1
    fi

    (
        cd "$manifest_dir" && \
        shasum -a 256 -c "$(basename "$manifest_path")" >/dev/null
    ) || {
        echo "Backup integrity check failed for dump/globals pair."
        exit 1
    }

    if [ ! -f "$backup_path" ] || [ ! -f "$globals_path" ]; then
        echo "Backup integrity check failed because backup inputs are missing."
        exit 1
    fi
}

latest_backup_path() {
    #R005: Resolve newest local encrypted dump when --from is not provided.
    local latest=""
    local candidate=""
    shopt -s nullglob
    for candidate in "$BACKUP_DIR"/*.dump.gpg; do
        if [ -z "$latest" ] || [ "$candidate" -nt "$latest" ]; then
            latest="$candidate"
        fi
    done
    if [ -n "$latest" ]; then
        shopt -u nullglob
        echo "$latest"
        return
    fi
    #R110: Backward-compatible fallback for legacy plaintext dumps.
    for candidate in "$BACKUP_DIR"/*.dump; do
        if [ -z "$latest" ] || [ "$candidate" -nt "$latest" ]; then
            latest="$candidate"
        fi
    done
    shopt -u nullglob
    echo "$latest"
}

encryption_env_var_for_field() {
    local field_name="$1"
    local normalized=""
    normalized="$(printf '%s' "$field_name" | tr '[:lower:]' '[:upper:]')"
    normalized="${normalized//[^A-Z0-9]/_}"
    echo "POSTGRES_BACKUP_ENCRYPTION_${normalized}"
}

read_backup_encryption_field() {
    local field_name="$1"
    local env_name=""
    local value=""
    env_name="$(encryption_env_var_for_field "$field_name")"
    value="$(1psa -f "$BACKUP_ENCRYPTION_ITEM" "$field_name" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
        value="${!env_name:-}"
    fi
    printf '%s' "$value"
}

init_gpg_home() {
    if [[ -n "$GPG_HOME" ]]; then
        return
    fi
    GPG_HOME="$(mktemp -d)"
    cleanup_paths+=("$GPG_HOME")
    chmod 700 "$GPG_HOME"
}

load_backup_decryption_material() {
    local encryption_type=""
    local gpg_private_key=""
    local gpg_passphrase=""
    local private_key_path=""

    if [[ -n "$GPG_HOME" ]]; then
        return
    fi
    encryption_type="$(read_backup_encryption_field "type")"
    if [[ "$encryption_type" != "gpg" ]]; then
        echo "Backup decryption requires type=gpg in ${BACKUP_ENCRYPTION_ITEM} or POSTGRES_BACKUP_ENCRYPTION_TYPE."
        exit 1
    fi
    gpg_private_key="$(read_backup_encryption_field "gpg_private_key")"
    if [[ -z "$gpg_private_key" ]]; then
        echo "Backup decryption requires gpg_private_key in ${BACKUP_ENCRYPTION_ITEM} or POSTGRES_BACKUP_ENCRYPTION_GPG_PRIVATE_KEY."
        exit 1
    fi
    gpg_passphrase="$(read_backup_encryption_field "gpg_private_key_passphrase")"
    if [[ -z "$gpg_passphrase" ]]; then
        echo "Backup decryption requires gpg_private_key_passphrase in ${BACKUP_ENCRYPTION_ITEM} or POSTGRES_BACKUP_ENCRYPTION_GPG_PRIVATE_KEY_PASSPHRASE."
        exit 1
    fi
    init_gpg_home
    private_key_path="$(mktemp)"
    cleanup_paths+=("$private_key_path")
    printf '%s\n' "$gpg_private_key" >"$private_key_path"
    gpg --batch --yes --homedir "$GPG_HOME" --pinentry-mode loopback --passphrase "$gpg_passphrase" --import "$private_key_path" >/dev/null 2>&1
}

decrypt_backup_artifact() {
    local encrypted_path="$1"
    local output_path="$2"
    local gpg_passphrase=""

    gpg_passphrase="$(read_backup_encryption_field "gpg_private_key_passphrase")"
    gpg --batch --yes --homedir "$GPG_HOME" --pinentry-mode loopback --passphrase "$gpg_passphrase" --output "$output_path" --decrypt "$encrypted_path" >/dev/null 2>&1
    chmod 600 "$output_path"
}

#R005: Parse optional --from backup source argument.
#R040: Parse optional --table table scope argument.
while [ "$#" -gt 0 ]; do
    case "$1" in
        --from)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            BACKUP_PATH="$2"
            shift 2
            ;;
        --table)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            TABLE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

#R010: Require restore dependencies before running restore commands.
if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

#R010: Require pg_restore.
if ! command -v pg_restore >/dev/null 2>&1; then
    echo "pg_restore is required but was not found on PATH."
    exit 1
fi

#R010: Require psql.
if ! command -v psql >/dev/null 2>&1; then
    echo "psql is required but was not found on PATH."
    exit 1
fi

#R110: Require gpg for encrypted backup restore flows.
if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required but was not found on PATH."
    exit 1
fi

#R085: Refuse restore when the profile helper is missing so we never silently fall back
#R085: to a stale hard-coded target.
if [[ ! -x "$DB_PROFILE_HELPER" ]]; then
    echo "DB profile helper is missing or not executable: ${DB_PROFILE_HELPER}"
    exit 1
fi

#R085: Whitelist the profile export keys so we cannot accidentally source arbitrary env.
load_profile_exports_from_file() {
    local exports_file="$1"
    local invalid_lines=""
    invalid_lines="$(awk '
        !/^(export )?[A-Za-z_][A-Za-z0-9_]*=.*/ { print; next }
        {
            key=$0
            sub(/^export[[:space:]]+/, "", key)
            sub(/=.*/, "", key)
            if (key !~ /^(DB_DIALECT|PROFILE_NAME|PROFILE_TARGET|PG_HOST|PG_PORT|PG_DBNAME|PG_USER|PG_SSLMODE|PG_SEARCH_PATH|PG_RUNTIME_ROLE|PG_ONEPSA_ITEM|SQLITE_PATH|SQLCIPHER_KEY)$/) {
                print
            }
        }
    ' "$exports_file")"
    if [[ -n "$invalid_lines" ]]; then
        echo "Refusing to load unexpected profile export lines:"
        printf '%s\n' "$invalid_lines"
        return 1
    fi
    unset DB_DIALECT PROFILE_NAME PROFILE_TARGET PG_HOST PG_PORT PG_DBNAME PG_USER
    unset PG_SSLMODE PG_SEARCH_PATH PG_RUNTIME_ROLE PG_ONEPSA_ITEM SQLITE_PATH SQLCIPHER_KEY
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

#R005: Default to latest backup when --from is omitted.
if [ -z "$BACKUP_PATH" ]; then
    BACKUP_PATH="$(latest_backup_path)"
fi

#R086: Support SQLite restore through the existing restore entrypoint.
if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
    if [ -n "$TABLE_NAME" ]; then
        echo "--table scoped restore is not supported for sqlite targets."
        exit 1
    fi
    if [ -z "$BACKUP_PATH" ]; then
        echo "No backup file found in $BACKUP_DIR"
        exit 1
    fi
    if [ ! -f "$BACKUP_PATH" ]; then
        echo "Backup file does not exist: $BACKUP_PATH"
        exit 1
    fi
    BACKUP_INPUT_PATH="$BACKUP_PATH"
    if [[ "$BACKUP_PATH" == *.gpg ]]; then
        load_backup_decryption_material
        BACKUP_INPUT_PATH="$(mktemp)"
        cleanup_paths+=("$BACKUP_INPUT_PATH")
        decrypt_backup_artifact "$BACKUP_PATH" "$BACKUP_INPUT_PATH"
    fi
    SQLITE_DB_PATH="${SQLITE_PATH:-}"
    if [ -z "$SQLITE_DB_PATH" ]; then
        echo "SQLite restore requires SQLITE_PATH from db profile export."
        exit 1
    fi
    cp "$BACKUP_INPUT_PATH" "$SQLITE_DB_PATH"
    echo "Restore complete from: $BACKUP_PATH"
    exit 0
fi

#R020: Require backup dump file to exist.
if [ -z "$BACKUP_PATH" ]; then
    echo "No backup file found in $BACKUP_DIR"
    exit 1
fi

#R020: Require specified backup path to exist.
if [ ! -f "$BACKUP_PATH" ]; then
    echo "Backup file does not exist: $BACKUP_PATH"
    exit 1
fi
BACKUP_INPUT_PATH="$BACKUP_PATH"
if [[ "$BACKUP_PATH" == *.gpg ]]; then
    load_backup_decryption_material
    BACKUP_INPUT_PATH="$(mktemp)"
    cleanup_paths+=("$BACKUP_INPUT_PATH")
    decrypt_backup_artifact "$BACKUP_PATH" "$BACKUP_INPUT_PATH"
fi

#R040: Parse optional --table scope into schema/table components used by both targets.
RESTORE_TABLE_ARGS=()
if [ -n "$TABLE_NAME" ]; then
    if [[ "$TABLE_NAME" == *.* ]]; then
        TABLE_SCHEMA="${TABLE_NAME%%.*}"
        TABLE_RELATION="${TABLE_NAME#*.}"
    else
        TABLE_SCHEMA="teller"
        TABLE_RELATION="$TABLE_NAME"
    fi
    #R101: Validate scoped restore schema/table identifiers before repair SQL.
    if ! is_valid_pg_identifier "$TABLE_SCHEMA"; then
        echo "Invalid schema identifier supplied to --table: ${TABLE_SCHEMA}"
        exit 1
    fi
    if ! is_valid_pg_identifier "$TABLE_RELATION"; then
        echo "Invalid table identifier supplied to --table: ${TABLE_RELATION}"
        exit 1
    fi
    RESTORE_TABLE_ARGS=(--schema "$TABLE_SCHEMA" --table "$TABLE_RELATION")
fi

#R090: Managed-target restore refuses full restore (cannot CREATE DATABASE / replay globals);
#R090: only --table scoped restore is supported, using the profile's user against the
#R090: direct (non-pooler) host with the profile's 1psa item or TELLER_DB_PASSWORD env override.
if [[ "${PROFILE_TARGET:-local}" == "managed" ]]; then
    if [ -z "$TABLE_NAME" ]; then
        echo "Refusing full restore against managed target (profile=${PROFILE_NAME})."
        echo "Managed targets cannot accept CREATE-DATABASE-style restore or globals replay."
        echo "Re-run with --table schema.table_name for a scoped restore."
        exit 1
    fi

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
    require_nonempty_env "Managed direct restore profile" PROFILE_NAME PG_HOST PG_PORT PG_DBNAME PG_USER

    MANAGED_PASSWORD="${TELLER_DB_PASSWORD:-}"
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        if [[ -z "${PG_ONEPSA_ITEM:-}" ]]; then
            echo "Managed restore requires PG_ONEPSA_ITEM (from config/db-profiles.json) or TELLER_DB_PASSWORD."
            exit 1
        fi
        MANAGED_PASSWORD="$(1psa -p "$PG_ONEPSA_ITEM")"
    fi
    if [[ -z "$MANAGED_PASSWORD" ]]; then
        echo "Failed to read managed DB password (item: ${PG_ONEPSA_ITEM:-<unset>})"
        exit 1
    fi

    echo "ℹ️  Restoring managed schema-scoped table via profile=${PROFILE_NAME} host=${PG_HOST} port=${PG_PORT} db=${PG_DBNAME} user=${PG_USER} table=${TABLE_SCHEMA}.${TABLE_RELATION}"
    PGPASSWORD="$MANAGED_PASSWORD" PGSSLMODE="$PG_SSLMODE" pg_restore \
        -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DBNAME" \
        --clean --if-exists "${RESTORE_TABLE_ARGS[@]}" "$BACKUP_INPUT_PATH"

    #R035: Print completion status with source backup path.
    echo "Restore complete from: $BACKUP_PATH"
    exit 0
fi

#R015: Local target uses configurable postgres admin via 1psa.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
#R070: Local target uses configurable teller credential for post-restore re-sync.
TELLER_PSA_ITEM="${TELLER_PSA_ITEM:-localhost_postgres_teller}"
TELLER_PSA_FIELD="${TELLER_PSA_FIELD:-password}"
#R095: Honor DATABASE_NAME env override for backward compatibility, otherwise use the resolved profile DB.
#R100: Validate full-restore DATABASE_NAME identifier before destructive checks.
DATABASE_NAME="${DATABASE_NAME:-$PG_DBNAME}"
if ! is_valid_pg_identifier "$DATABASE_NAME"; then
    echo "Resolved DATABASE_NAME is not a valid PostgreSQL identifier: ${DATABASE_NAME}"
    exit 1
fi

#R035: Run fail-fast SQL against the target database as postgres.
run_psql_target() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d "$DATABASE_NAME" "$@"
}

#R050: Reapply deploy-time invariants after scoped table restore.
repair_scoped_table_restore() {
    if [ "${TABLE_SCHEMA}" != "teller" ] || [ -z "${TABLE_RELATION}" ]; then
        return
    fi

    #R055: Ensure shared updated_at trigger function exists for teller schema tables.
    run_psql_target <<'SQL'
CREATE OR REPLACE FUNCTION teller.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
SQL

    #R060: Recreate updated_at trigger for restored table when that column exists.
    #R101: Identifiers are pre-validated; use direct SQL for psql -c compatibility.
    has_updated_at="$(
        run_psql_target -tAc "
            SELECT 1
            FROM information_schema.columns columns
            WHERE columns.table_schema = '${TABLE_SCHEMA}'
              AND columns.table_name = '${TABLE_RELATION}'
              AND columns.column_name = 'updated_at'
            LIMIT 1;
        "
    )"
    if [ "${has_updated_at}" = "1" ]; then
        trigger_name="update_${TABLE_RELATION}_updated_at"
        run_psql_target -c "DROP TRIGGER IF EXISTS \"${trigger_name}\" ON \"${TABLE_SCHEMA}\".\"${TABLE_RELATION}\";"
        run_psql_target -c "CREATE TRIGGER \"${trigger_name}\" BEFORE UPDATE ON \"${TABLE_SCHEMA}\".\"${TABLE_RELATION}\" FOR EACH ROW EXECUTE FUNCTION teller.update_updated_at();"
    fi

    #R065: Reapply known table-specific DDL adjustments from deploy script.
    if [ "${TABLE_RELATION}" = "transaction_nys_snw_category" ]; then
        run_psql_target <<'SQL'
ALTER TABLE teller.transaction_nys_snw_category
    DROP CONSTRAINT IF EXISTS transaction_nys_snw_category_transaction_id_fkey,
    ADD CONSTRAINT transaction_nys_snw_category_transaction_id_fkey
    FOREIGN KEY (transaction_id)
    REFERENCES teller.transaction(transaction_id)
    ON DELETE CASCADE;
SQL
    fi
}

#R015: Resolve postgres password from configured 1psa item/field.
if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

#R070: Resolve teller password from configured 1psa item/field.
if [ "$TELLER_PSA_FIELD" = "password" ]; then
    TELLER_PASSWORD="$(1psa -p "$TELLER_PSA_ITEM")"
else
    TELLER_PASSWORD="$(1psa -f "$TELLER_PSA_ITEM" "$TELLER_PSA_FIELD")"
fi

#R015: Refuse restore when postgres password lookup is empty.
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

#R070: Refuse restore when teller password lookup is empty.
if [ -z "$TELLER_PASSWORD" ]; then
    echo "Failed to read teller password from 1psa item: $TELLER_PSA_ITEM"
    exit 1
fi

#R020: Require matching globals dump file only for full restore mode.
#R102: Require dump/globals integrity manifest verification before globals replay.
if [ -z "$TABLE_NAME" ]; then
    if [[ "$BACKUP_PATH" == *.dump.gpg ]]; then
        GLOBALS_BACKUP_PATH="${BACKUP_PATH%.dump.gpg}_globals.sql.gpg"
        MANIFEST_PATH="${BACKUP_PATH%.dump.gpg}.manifest.sha256"
    else
        GLOBALS_BACKUP_PATH="${BACKUP_PATH%.dump}_globals.sql"
        MANIFEST_PATH="${BACKUP_PATH%.dump}.manifest.sha256"
        echo "⚠️  Plaintext backup detected. Recreate with 97_backup_database.sh for encrypted artifacts."
    fi
    if [ ! -f "$GLOBALS_BACKUP_PATH" ]; then
        echo "Matching globals backup is missing: $GLOBALS_BACKUP_PATH"
        echo "Recreate backup with 97_backup_database.sh to include roles and grants."
        exit 1
    fi
    verify_backup_manifest "$BACKUP_PATH" "$GLOBALS_BACKUP_PATH" "$MANIFEST_PATH"
    GLOBALS_RESTORE_PATH="$GLOBALS_BACKUP_PATH"
    if [[ "$GLOBALS_BACKUP_PATH" == *.gpg ]]; then
        GLOBALS_RESTORE_PATH="$(mktemp)"
        cleanup_paths+=("$GLOBALS_RESTORE_PATH")
        decrypt_backup_artifact "$GLOBALS_BACKUP_PATH" "$GLOBALS_RESTORE_PATH"
    fi
fi

#R025: Refuse full restore into db that already contains teller schema.
database_exists="$(
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '${DATABASE_NAME}';"
)"
if [ "$database_exists" = "1" ]; then
    schema_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d "$DATABASE_NAME" -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='teller';")"
    if [ "$schema_exists" = "1" ] && [ -z "$TABLE_NAME" ]; then
        echo "Schema teller already exists in ${DATABASE_NAME}; refusing full restore."
        echo "Pass --table schema.table_name to run table-scoped restore into existing schema."
        exit 1
    fi
fi

#R030: In full restore mode, restore globals first, then restore database dump.
if [ -n "$TABLE_NAME" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d "$DATABASE_NAME" --clean --if-exists "${RESTORE_TABLE_ARGS[@]}" "$BACKUP_INPUT_PATH"
    repair_scoped_table_restore
else
    #R030: Globals replay may encounter pre-existing cluster roles (for example app_owner).
    # Retry in non-stop mode only for duplicate-role conflicts so remaining grants still apply.
    globals_err_log="$(mktemp)"
    if ! PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f "$GLOBALS_RESTORE_PATH" 2>"$globals_err_log"; then
        if rg -q 'role ".*" already exists' "$globals_err_log"; then
            echo "⚠️  Globals replay hit existing roles; retrying in non-stop mode to apply remaining statements."
            if ! PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=0 -U postgres -d postgres -f "$GLOBALS_RESTORE_PATH"; then
                rm -f "$globals_err_log"
                echo "Globals replay failed after duplicate-role retry."
                exit 1
            fi
        else
            cat "$globals_err_log"
            rm -f "$globals_err_log"
            echo "Globals replay failed."
            exit 1
        fi
    fi
    rm -f "$globals_err_log"
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d postgres --clean --if-exists --create "$BACKUP_INPUT_PATH"
    #R075: Re-sync teller role credential to live 1psa secret after globals restore.
    escaped_teller_password="${TELLER_PASSWORD//\'/\'\'}"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
        -c "ALTER USER teller WITH PASSWORD '${escaped_teller_password}';"
    #R080: Verify teller login with the same 1psa credential to catch stale globals drift.
    if ! PGPASSWORD="$TELLER_PASSWORD" psql -w -v ON_ERROR_STOP=1 -U teller -d "$DATABASE_NAME" -tAc "SELECT 1;" >/dev/null; then
        echo "Restore completed but teller authentication failed with 1psa secret from $TELLER_PSA_ITEM."
        exit 1
    fi
fi
#R045: Support combining --from with --table for scoped restore from explicit dump.
#R035: Print completion status with source backup path.
echo "Restore complete from: $BACKUP_PATH"
