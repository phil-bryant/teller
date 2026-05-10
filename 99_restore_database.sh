#!/bin/bash
#R001: Enforce strict shell mode and secure default file permissions.
umask 007
set -euo pipefail

#R015: Configure credential source and target database via environment overrides.
POSTGRES_PSA_ITEM="${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}"
POSTGRES_PSA_FIELD="${POSTGRES_PSA_FIELD:-password}"
TELLER_PSA_ITEM="${TELLER_PSA_ITEM:-localhost_postgres_teller}"
TELLER_PSA_FIELD="${TELLER_PSA_FIELD:-password}"
DATABASE_NAME="${DATABASE_NAME:-prod}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
BACKUP_PATH=""
GLOBALS_BACKUP_PATH=""
TABLE_NAME=""
TABLE_SCHEMA=""
TABLE_RELATION=""

usage() {
    echo "Usage: $0 [--from /path/to/backup.dump] [--table table_name|schema.table_name]"
}

latest_backup_path() {
    #R005: Resolve newest local dump when --from is not provided.
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
    has_updated_at="$(
        run_psql_target -tAc "
            SELECT 1
            FROM information_schema.columns columns
            WHERE columns.table_schema = 'teller'
              AND columns.table_name = '${TABLE_RELATION}'
              AND columns.column_name = 'updated_at'
            LIMIT 1;
        "
    )"
    if [ "${has_updated_at}" = "1" ]; then
        run_psql_target -c \
"DROP TRIGGER IF EXISTS update_${TABLE_RELATION}_updated_at ON teller.${TABLE_RELATION};
CREATE TRIGGER update_${TABLE_RELATION}_updated_at
    BEFORE UPDATE ON teller.${TABLE_RELATION}
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();"
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

#R015: Refuse restore when password lookup is empty.
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Failed to read postgres password from 1psa item: $POSTGRES_PSA_ITEM"
    exit 1
fi

#R070: Refuse restore when teller password lookup is empty.
if [ -z "$TELLER_PASSWORD" ]; then
    echo "Failed to read teller password from 1psa item: $TELLER_PSA_ITEM"
    exit 1
fi

#R005: Default to latest backup when --from is omitted.
if [ -z "$BACKUP_PATH" ]; then
    BACKUP_PATH="$(latest_backup_path)"
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

#R020: Require matching globals dump file only for full restore mode.
if [ -z "$TABLE_NAME" ]; then
    GLOBALS_BACKUP_PATH="${BACKUP_PATH%.dump}_globals.sql"
    if [ ! -f "$GLOBALS_BACKUP_PATH" ]; then
        echo "Matching globals backup is missing: $GLOBALS_BACKUP_PATH"
        echo "Recreate backup with 97_backup_database.sh to include roles and grants."
        exit 1
    fi
fi

#R025: Refuse full restore into db that already contains teller schema.
database_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}';")"
if [ "$database_exists" = "1" ]; then
    schema_exists="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d "$DATABASE_NAME" -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='teller';")"
    if [ "$schema_exists" = "1" ] && [ -z "$TABLE_NAME" ]; then
        echo "Schema teller already exists in ${DATABASE_NAME}; refusing full restore."
        echo "Pass --table schema.table_name to run table-scoped restore into existing schema."
        exit 1
    fi
fi

#R040: Add table scope to restore when --table is provided.
RESTORE_TABLE_ARGS=()
if [ -n "$TABLE_NAME" ]; then
    if [[ "$TABLE_NAME" == *.* ]]; then
        TABLE_SCHEMA="${TABLE_NAME%%.*}"
        TABLE_RELATION="${TABLE_NAME#*.}"
    else
        TABLE_SCHEMA="teller"
        TABLE_RELATION="$TABLE_NAME"
    fi
    RESTORE_TABLE_ARGS=(--schema "$TABLE_SCHEMA" --table "$TABLE_RELATION")
fi

#R030: In full restore mode, restore globals first, then restore database dump.
if [ -n "$TABLE_NAME" ]; then
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d "$DATABASE_NAME" --clean --if-exists "${RESTORE_TABLE_ARGS[@]}" "$BACKUP_PATH"
    repair_scoped_table_restore
else
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f "$GLOBALS_BACKUP_PATH"
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U postgres -d postgres --clean --if-exists --create "$BACKUP_PATH"
    #R075: Re-sync teller role credential to live 1psa secret after globals restore.
    PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
        -v teller_password="$TELLER_PASSWORD" \
        -c "ALTER USER teller WITH PASSWORD :'teller_password';"
    #R080: Verify teller login with the same 1psa credential to catch stale globals drift.
    if ! PGPASSWORD="$TELLER_PASSWORD" psql -w -v ON_ERROR_STOP=1 -U teller -d "$DATABASE_NAME" -tAc "SELECT 1;" >/dev/null; then
        echo "Restore completed but teller authentication failed with 1psa secret from $TELLER_PSA_ITEM."
        exit 1
    fi
fi
#R045: Support combining --from with --table for scoped restore from explicit dump.
#R035: Print completion status with source backup path.
echo "Restore complete from: $BACKUP_PATH"
