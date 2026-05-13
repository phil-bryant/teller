#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Resolve repo root from script path for deterministic relative references.
cd "$SCRIPT_DIR"

REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./.security-reports}"
RUN_TELLER_CANARY="${RUN_TELLER_CANARY:-true}"
RUN_POSTGRES_FRESHNESS="${RUN_POSTGRES_FRESHNESS:-true}"
FAIL_ON_MAJOR="${DEPENDENCY_FAIL_ON_MAJOR:-false}"
FAIL_ON_DIRECT_OUTDATED="${DEPENDENCY_FAIL_ON_DIRECT_OUTDATED:-true}"
POSTGRES_FAIL_ON_STALE="${POSTGRES_FAIL_ON_STALE:-false}"
POSTGRES_CHECK_SERVER_VERSION="${POSTGRES_CHECK_SERVER_VERSION:-true}"
POSTGRES_CHECK_CVES="${POSTGRES_CHECK_CVES:-true}"
POSTGRES_FAIL_ON_CVE="${POSTGRES_FAIL_ON_CVE:-true}"
POSTGRES_REFRESH_CVE_SNAPSHOT="${POSTGRES_REFRESH_CVE_SNAPSHOT:-true}"
POSTGRES_CVE_SNAPSHOT_FILE="${POSTGRES_CVE_SNAPSHOT_FILE:-./security/postgres-cve-snapshot.json}"
POSTGRES_CVE_POLICY_FILE="${POSTGRES_CVE_POLICY_FILE:-./security/postgres-cve-policy.json}"
POSTGRES_SERVER_PSQL_ARGS="${POSTGRES_SERVER_PSQL_ARGS:-}"
POSTGRES_SERVER_PSA_ITEM="${POSTGRES_SERVER_PSA_ITEM:-localhost_postgres_teller}"
POSTGRES_SERVER_PSA_FIELD="${POSTGRES_SERVER_PSA_FIELD:-password}"

mkdir -p "$REPORT_DIR"

PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"
#R005: Prefer active virtualenv interpreter, then local teller-venv, then system python.
if [[ -z "$PROJECT_PYTHON" ]]; then
  if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ -x "${VIRTUAL_ENV}/bin/python" ]]; then
    PROJECT_PYTHON="${VIRTUAL_ENV}/bin/python"
  elif [[ -x "./teller-venv/bin/python" ]]; then
    PROJECT_PYTHON="./teller-venv/bin/python"
  else
    PROJECT_PYTHON="python3"
  fi
fi

if [[ ! -x "$PROJECT_PYTHON" ]] && [[ "$PROJECT_PYTHON" != "python3" ]]; then
  echo "❌ Project python not executable: $PROJECT_PYTHON"
  exit 1
fi

echo "▶ Running dependency freshness checks with ${PROJECT_PYTHON}"
#R010: Emit machine-readable and text freshness reports with optional major-version gate.
DEPENDENCY_FRESHNESS_ARGS=(
  ./scripts/check_dependency_freshness.py
  --output-json "${REPORT_DIR}/dependency-freshness.json"
  --output-text "${REPORT_DIR}/dependency-freshness.txt"
)
if [[ "$FAIL_ON_MAJOR" == "true" ]]; then
  DEPENDENCY_FRESHNESS_ARGS+=(--fail-on-major)
fi
if [[ "$FAIL_ON_DIRECT_OUTDATED" == "true" ]]; then
  DEPENDENCY_FRESHNESS_ARGS+=(--fail-on-direct-outdated)
fi
"$PROJECT_PYTHON" "${DEPENDENCY_FRESHNESS_ARGS[@]}"

if [[ "$RUN_TELLER_CANARY" == "true" ]]; then
  #R015: Run optional Teller API compatibility/drift canary checks.
  echo "▶ Running Teller API drift checks"
  "$PROJECT_PYTHON" ./scripts/check_teller_api_drift.py \
    --output-json "${REPORT_DIR}/teller-api-drift.json" \
    --output-text "${REPORT_DIR}/teller-api-drift.txt"
fi

#R020: Run optional PostgreSQL version freshness checks and emit freshness artifacts.
if [[ "$RUN_POSTGRES_FRESHNESS" == "true" ]]; then
  echo "▶ Running PostgreSQL freshness checks"
  if [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]] && [[ -z "$POSTGRES_SERVER_PSQL_ARGS" ]]; then
    POSTGRES_SERVER_PSQL_ARGS="-h localhost -U teller -d prod"
  fi
  if [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]] && [[ -z "${PGPASSWORD:-}" ]] && command -v 1psa >/dev/null 2>&1; then
    if [[ "$POSTGRES_SERVER_PSA_FIELD" == "password" ]]; then
      postgres_password="$(1psa -p "$POSTGRES_SERVER_PSA_ITEM" 2>/dev/null || true)"
      export PGPASSWORD="$postgres_password"
    else
      postgres_password="$(1psa -f "$POSTGRES_SERVER_PSA_ITEM" "$POSTGRES_SERVER_PSA_FIELD" 2>/dev/null || true)"
      export PGPASSWORD="$postgres_password"
    fi
  fi
  POSTGRES_FRESHNESS_ARGS=(
    ./scripts/check_postgres_freshness.py
    --output-json "${REPORT_DIR}/postgres-freshness.json"
    --output-text "${REPORT_DIR}/postgres-freshness.txt"
  )
  if [[ -n "${POSTGRES_MIN_CLIENT_VERSION:-}" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--min-client-version "${POSTGRES_MIN_CLIENT_VERSION}")
  fi
  if [[ -n "${POSTGRES_MIN_SERVER_VERSION:-}" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--min-server-version "${POSTGRES_MIN_SERVER_VERSION}")
  fi
  if [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--check-server-version)
    if [[ -n "$POSTGRES_SERVER_PSQL_ARGS" ]]; then
      POSTGRES_FRESHNESS_ARGS+=("--server-psql-args=${POSTGRES_SERVER_PSQL_ARGS}")
    fi
  fi
  #R025: Refresh PostgreSQL CVE advisories and evaluate client/server against affected ranges.
  if [[ "$POSTGRES_CHECK_CVES" == "true" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--check-cves --cve-snapshot "${POSTGRES_CVE_SNAPSHOT_FILE}" --cve-policy "${POSTGRES_CVE_POLICY_FILE}")
    if [[ "$POSTGRES_REFRESH_CVE_SNAPSHOT" == "true" ]]; then
      POSTGRES_FRESHNESS_ARGS+=(--refresh-cve-snapshot)
    fi
  fi
  if [[ "$POSTGRES_FAIL_ON_STALE" == "true" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--fail-on-stale)
  fi
  if [[ "$POSTGRES_FAIL_ON_CVE" == "true" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--fail-on-cve)
  fi
  if [[ -n "${POSTGRES_SERVER_DSN:-}" ]]; then
    POSTGRES_FRESHNESS_ARGS+=(--server-dsn "${POSTGRES_SERVER_DSN}")
  fi
  "$PROJECT_PYTHON" "${POSTGRES_FRESHNESS_ARGS[@]}"
fi

echo "✅ Dependency freshness checks completed. Reports: ${REPORT_DIR}"
