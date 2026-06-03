#!/usr/bin/env bash
#R001: Resolve a DB profile and emit shell `KEY=value` exports for sourcing.
#R005: Optional --profile <name> overrides TELLER_DB_PROFILE for this resolution.
#R010: Fail clearly when profile resolution cannot produce export values.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

OVERRIDE_PROFILE=""
while (( $# > 0 )); do
    case "$1" in
        --profile)
            shift
            OVERRIDE_PROFILE="${1:-}"
            ;;
        --profile=*)
            OVERRIDE_PROFILE="${1#--profile=}"
            ;;
        --help|-h)
            echo "usage: db_profile_export.sh [--profile <name>]"
            exit 0
            ;;
        *)
            echo "unknown arg: $1" >&2
            exit 2
            ;;
    esac
    shift || true
done

PYTHON_BIN="${TELLER_PYTHON:-${REPO_ROOT}/teller-venv/bin/python3}"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="$(command -v python3)"
fi

if [[ -n "$OVERRIDE_PROFILE" ]]; then
    export TELLER_DB_PROFILE="$OVERRIDE_PROFILE"
fi

PYTHONPATH="${REPO_ROOT}/src:${REPO_ROOT}${PYTHONPATH:+:${PYTHONPATH}}" "$PYTHON_BIN" - <<'PY' | awk '/^[A-Z_][A-Z0-9_]*=.*/ { print }'
import sys
import shlex
from pathlib import Path
from teller.teller_db_profile import ProfileError, resolve_profile

try:
    profile = resolve_profile()
except ProfileError as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(1)
is_sqlite_profile = profile.target == "sqlite" or profile.name == "sqlite"
sqlite_path = profile.sqlite_path
if is_sqlite_profile and not sqlite_path:
    sqlite_path = str(Path.cwd() / ".database" / "teller.sqlite3")
fields = {
    "DB_DIALECT": "sqlite" if is_sqlite_profile else "postgresql",
    "PROFILE_NAME": profile.name,
    "PROFILE_TARGET": "sqlite" if is_sqlite_profile else profile.target,
    "PG_HOST": profile.host,
    "PG_PORT": str(profile.port),
    "PG_DBNAME": profile.dbname,
    "PG_USER": profile.user,
    "PG_SSLMODE": profile.sslmode,
    "PG_SEARCH_PATH": profile.search_path,
    "PG_RUNTIME_ROLE": profile.runtime_role,
    "PG_ONEPSA_ITEM": profile.onepsa_item,
    "SQLITE_PATH": sqlite_path,
    "SQLCIPHER_KEY": profile.sqlcipher_key,
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(value)}")
PY
