#!/bin/bash
umask 007
set -euo pipefail

POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
DATABASE_NAME="${DATABASE_NAME:-prod}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
BACKUP_BASENAME="${DATABASE_NAME}_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}.dump"
GLOBALS_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_BASENAME}_globals.sql"

if ! command -v 1psa >/dev/null 2>&1; then
    echo "1psa is required but was not found on PATH."
    exit 1
fi

if ! command -v pg_dump >/dev/null 2>&1; then
    echo "pg_dump is required but was not found on PATH."
    exit 1
fi

if ! command -v pg_dumpall >/dev/null 2>&1; then
    echo "pg_dumpall is required but was not found on PATH."
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

mkdir -p "$BACKUP_DIR"
chmod 770 "$BACKUP_DIR"

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U postgres -d "$DATABASE_NAME" -Fc -C -f "$BACKUP_PATH"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres --globals-only -f "$GLOBALS_BACKUP_PATH"

chmod 660 "$BACKUP_PATH"
chmod 660 "$GLOBALS_BACKUP_PATH"
echo "Backup written: $BACKUP_PATH"
echo "Globals written: $GLOBALS_BACKUP_PATH"
