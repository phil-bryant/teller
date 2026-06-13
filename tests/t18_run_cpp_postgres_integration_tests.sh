#!/usr/bin/env bash
# C++ PostgreSQL integration lane: provisions a scratch database from the
# committed postgres DDL, runs the [postgres]-tagged Catch2 cases against it,
# and drops the database afterwards.
#
# Admin credentials resolve from TELLER_TEST_PG_ADMIN_CONNINFO (libpq keyword
# string with CREATE DATABASE permission) or, failing that, the documented
# ~/.env fallback item LOCALHOST_POSTGRES_POSTGRES. Without reachable admin
# credentials the lane skips cleanly (exit 0) so machines without a local
# PostgreSQL deployment stay green.
set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE_DIR="${REPO_ROOT}/src/core"
# Lane-private build tree: parallel lanes must not race t15's cmake configure.
BUILD_DIR="${CORE_DIR}/build-pg"
SQL_DIR="${REPO_ROOT}/src/sql/postgres"

env_item_field() {
  #R001: Reads "<item>.<field>=value" lines from ~/.env (teller_db_profile fallback format).
  local item="$1" field="$2"
  [[ -f "${HOME}/.env" ]] || return 0
  sed -n "s/^${item}\.${field}=\(.*\)$/\1/p" "${HOME}/.env" | head -1
}

PG_HOST=""
PG_PORT="5432"
PG_USER=""
PG_PASSWORD=""
if [[ -n "${TELLER_TEST_PG_ADMIN_CONNINFO:-}" ]]; then
  for pair in ${TELLER_TEST_PG_ADMIN_CONNINFO}; do
    case "${pair}" in
      host=*) PG_HOST="${pair#host=}" ;;
      port=*) PG_PORT="${pair#port=}" ;;
      user=*) PG_USER="${pair#user=}" ;;
      password=*) PG_PASSWORD="${pair#password=}" ;;
    esac
  done
else
  PG_HOST="$(env_item_field LOCALHOST_POSTGRES_POSTGRES host)"
  PG_PORT="$(env_item_field LOCALHOST_POSTGRES_POSTGRES port)"
  PG_USER="$(env_item_field LOCALHOST_POSTGRES_POSTGRES username)"
  PG_PASSWORD="$(env_item_field LOCALHOST_POSTGRES_POSTGRES password)"
  PG_HOST="${PG_HOST:-localhost}"
  PG_PORT="${PG_PORT:-5432}"
fi

if [[ -z "${PG_USER}" || -z "${PG_PASSWORD}" ]]; then
  echo "t18: no PostgreSQL admin credentials (TELLER_TEST_PG_ADMIN_CONNINFO or" \
       "HOME/.env LOCALHOST_POSTGRES_POSTGRES); skipping"
  exit 0
fi

run_psql() {
  #R005: All admin psql calls run non-interactively with strict error stops.
  PGPASSWORD="${PG_PASSWORD}" PGCONNECT_TIMEOUT=5 psql -w -v ON_ERROR_STOP=1 \
    -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"
}

if ! run_psql -d postgres -Atc "SELECT 1" >/dev/null 2>&1; then
  echo "t18: PostgreSQL at ${PG_HOST}:${PG_PORT} not reachable; skipping"
  exit 0
fi

cmake -S "${CORE_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)" --target tellercore_tests >/dev/null

SCRATCH_DB="teller_core_t18_$$"
cleanup() {
  #R010: The scratch database is always dropped, even on lane failure.
  run_psql -d postgres -Atc "DROP DATABASE IF EXISTS \"${SCRATCH_DB}\" WITH (FORCE)" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_psql -d postgres -Atc "DROP DATABASE IF EXISTS \"${SCRATCH_DB}\" WITH (FORCE)" >/dev/null
run_psql -d postgres -Atc "CREATE DATABASE \"${SCRATCH_DB}\"" >/dev/null
run_psql -d "${SCRATCH_DB}" -Atc "CREATE SCHEMA IF NOT EXISTS teller" >/dev/null

# Table DDL apply order mirrors the runner deploy golden (FK dependencies).
DDL_FILES=(
  teller_enums.sql
  teller_institution.sql
  teller_account_links.sql
  teller_account.sql
  teller_identity.sql
  teller_identity_name.sql
  teller_identity_email.sql
  teller_identity_phone_number.sql
  teller_identity_address_data.sql
  teller_identity_address.sql
  teller_account_identities.sql
  teller_routing_numbers.sql
  teller_account_details_links.sql
  teller_account_details.sql
  teller_account_balances_links.sql
  teller_account_balances.sql
  teller_transaction_type.sql
  teller_transaction_details_counterparty.sql
  teller_transaction_links.sql
  teller_transaction_details.sql
  teller_transaction.sql
)
for ddl_file in "${DDL_FILES[@]}"; do
  run_psql -d "${SCRATCH_DB}" -q -f "${SQL_DIR}/${ddl_file}" >/dev/null
done

TELLER_TEST_PG_CONNINFO="host=${PG_HOST} port=${PG_PORT} dbname=${SCRATCH_DB} user=${PG_USER} password=${PG_PASSWORD}" \
  "${BUILD_DIR}/tellercore_tests" "[postgres]"
echo "t18: C++ PostgreSQL integration tests passed"
