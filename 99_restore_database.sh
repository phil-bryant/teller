#!/bin/bash
umask 007
set -euo pipefail

POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
DATABASE_NAME="${DATABASE_NAME:-prod}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
BACKUP_PATH=""
GLOBALS_BACKUP_PATH=""

usage() {
    echo "Usage: $0 [--from /path/to/backup.dump]"
}

latest_backup_path() {
    local latest=""
    local candidate=""
    shopt -s nullglob
    for candidate in "$BACKUP_DIR"/*.dump; do
        if [ -z "$latest" ] || [ "$candidate" -nt "$latest" ]; then
            latest="$candidate"
        fi
    done
    shopt -u nullglob
    echo "$latest"
}

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

if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

if ! command -v pg_restore >/dev/null 2>&1; then
    echo "pg_restore is required but was not found on PATH."
    exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
    echo "psql is required but was not found on PATH."
    exit 1
fi

if [ "$POSTGRES_PSA_FIELD" = "password" ]; then
    POSTGRES_PASSWORD="$(1psa -p "$POSTGRES_PSA_ITEM")"
else
    POSTGRES_PASSWORD="$(1psa -f "$POSTGRES_PSA_ITEM" "$POSTGRES_PSA_FIELD")"
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

if [ -z "$BACKUP_PATH" ]; then
    BACKUP_PATH="$(latest_backup_path)"
fi

if [ -z "$BACKUP_PATH" ]; then
    echo "No backup file found in $BACKUP_DIR"
    exit 1
fi

if [ ! -f "$BACKUP_PATH" ]; then
    echo "Backup file does not exist: $BACKUP_PATH"
    exit 1
fi

GLOBALS_BACKUP_PATH="${BACKUP_PATH%.dump}_globals.sql"
if [ ! -f "$GLOBALS_BACKUP_PATH" ]; then
    echo "Matching globals backup is missing: $GLOBALS_BACKUP_PATH"
    echo "Recreate backup with 97_backup_database.sh to include roles and grants."
    exit 1
fi

database_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}';")"
if [ "$database_exists" = "1" ]; then
    schema_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d "$DATABASE_NAME" -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='teller';")"
    if [ "$schema_exists" = "1" ]; then
        echo "Schema teller already exists in ${DATABASE_NAME}; refusing to restore."
        exit 1
    fi
fi

PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -f "$GLOBALS_BACKUP_PATH"
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d postgres --clean --if-exists --create "$BACKUP_PATH"
echo "Restore complete from: $BACKUP_PATH"
