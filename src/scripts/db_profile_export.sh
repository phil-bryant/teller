#!/usr/bin/env bash
#R001: Resolve a DB profile and emit shell `KEY=value` exports for sourcing.
#R005: Optional --profile <name> overrides TELLER_DB_PROFILE for this resolution.
#R010: Fail clearly when profile resolution cannot produce export values.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

PYTHONPATH="${REPO_ROOT}/src:${REPO_ROOT}${PYTHONPATH:+:${PYTHONPATH}}" "$PYTHON_BIN" - <<'PY'
import sys
import shlex
from teller.teller_db_profile import ProfileError, resolve_profile

try:
    profile = resolve_profile()
except ProfileError as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(1)
fields = {
    "DB_DIALECT": "sqlite" if profile.target == "sqlite" else "postgresql",
    "PROFILE_NAME": profile.name,
    "PROFILE_TARGET": profile.target,
    "PG_HOST": profile.host,
    "PG_PORT": str(profile.port),
    "PG_DBNAME": profile.dbname,
    "PG_USER": profile.user,
    "PG_SSLMODE": profile.sslmode,
    "PG_SEARCH_PATH": profile.search_path,
    "PG_RUNTIME_ROLE": profile.runtime_role,
    "PG_ONEPSA_ITEM": profile.onepsa_item,
    "SQLITE_PATH": profile.sqlite_path,
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(value)}")
PY
