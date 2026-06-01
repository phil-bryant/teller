#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
#R001: Resolve repo root from script path for deterministic relative references.
cd "$REPO_ROOT"

REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./artifacts/security}"
RUN_POSTGRES_FRESHNESS="${RUN_POSTGRES_FRESHNESS:-true}"
RUN_TELLER_VERSION_FRESHNESS="${RUN_TELLER_VERSION_FRESHNESS:-true}"
RUN_BINARY_INTEGRITY_CHECK="${RUN_BINARY_INTEGRITY_CHECK:-true}"
BINARY_INTEGRITY_POLICY_FILE="${BINARY_INTEGRITY_POLICY_FILE:-./config/security/binary-integrity-policy.json}"
TELLER_API_BASELINE_VERSION="${TELLER_API_BASELINE_VERSION:-}"
TELLER_API_VERSION_FAIL_ON_NEW="${TELLER_API_VERSION_FAIL_ON_NEW:-false}"
TELLER_API_VERSION_SOURCES="${TELLER_API_VERSION_SOURCES:-https://teller.io/docs/api,https://api.teller.io/openapi.json,https://api.teller.io/swagger.json}"
TELLER_API_VERSION_DASHBOARD_URL="${TELLER_API_VERSION_DASHBOARD_URL:-https://teller.io/settings/application}"
TELLER_API_VERSION_DASHBOARD_PSA_ITEM="${TELLER_API_VERSION_DASHBOARD_PSA_ITEM:-TELLER_IO}"
TELLER_API_VERSION_DASHBOARD_USERNAME_FIELD="${TELLER_API_VERSION_DASHBOARD_USERNAME_FIELD:-username}"
TELLER_API_VERSION_DASHBOARD_PASSWORD_FIELD="${TELLER_API_VERSION_DASHBOARD_PASSWORD_FIELD:-password}"
TELLER_API_VERSION_DASHBOARD_OTP_FIELD="${TELLER_API_VERSION_DASHBOARD_OTP_FIELD:-one-time password}"
POSTGRES_FAIL_ON_STALE="${POSTGRES_FAIL_ON_STALE:-false}"
POSTGRES_CHECK_SERVER_VERSION="${POSTGRES_CHECK_SERVER_VERSION:-true}"
POSTGRES_CHECK_CVES="${POSTGRES_CHECK_CVES:-true}"
POSTGRES_FAIL_ON_CVE="${POSTGRES_FAIL_ON_CVE:-true}"
POSTGRES_REFRESH_CVE_SNAPSHOT="${POSTGRES_REFRESH_CVE_SNAPSHOT:-true}"
POSTGRES_CVE_SNAPSHOT_FILE="${POSTGRES_CVE_SNAPSHOT_FILE:-./config/security/postgres-cve-snapshot.json}"
POSTGRES_CVE_POLICY_FILE="${POSTGRES_CVE_POLICY_FILE:-./config/security/postgres-cve-policy.json}"
POSTGRES_SERVER_PSQL_ARGS="${POSTGRES_SERVER_PSQL_ARGS:-}"
POSTGRES_SERVER_PSA_ITEM="${POSTGRES_SERVER_PSA_ITEM:-localhost_postgres_teller}"
POSTGRES_SERVER_PSA_FIELD="${POSTGRES_SERVER_PSA_FIELD:-password}"

mkdir -p "$REPORT_DIR"

python_interpreter_usable() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" -c "import site" >/dev/null 2>&1
}

PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"
PROJECT_PYTHON_EXPLICIT=false
if [[ -n "${DEPENDENCY_CHECK_PYTHON:-}" ]]; then
  PROJECT_PYTHON_EXPLICIT=true
fi
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

if [[ "$PROJECT_PYTHON_EXPLICIT" != "true" ]]; then
  if ! python_interpreter_usable "$PROJECT_PYTHON"; then
    echo "⚠️ Selected interpreter '$PROJECT_PYTHON' is not usable; falling back to python3"
    PROJECT_PYTHON="python3"
  fi
fi

echo && echo "▶ Running dependency freshness checks with ${PROJECT_PYTHON}"
#R010: Emit machine-readable and text freshness reports with smart strict stale-dependency gates.
DEPENDENCY_FRESHNESS_ARGS=(
  ./src/scripts/check_dependency_freshness.py
  --output-json "${REPORT_DIR}/dependency-freshness.json"
  --output-text "${REPORT_DIR}/dependency-freshness.txt"
)
#R010: Actionable stale dependencies are mandatory blocking gate for this lane.
#R010: Do not weaken this gate; stale direct dependencies must be updated.
DEPENDENCY_FRESHNESS_ARGS+=(--fail-on-any-actionable-outdated)
DEPENDENCY_FRESHNESS_ARGS+=(--fail-on-direct-outdated)
#R012: Venv must not include explicitly installed packages outside requirements.txt.
DEPENDENCY_FRESHNESS_ARGS+=(--fail-on-venv-cruft)
"$PROJECT_PYTHON" "${DEPENDENCY_FRESHNESS_ARGS[@]}"

SECURITY_TOOLCHAIN_REQUIREMENTS_FILE="${SECURITY_TOOLCHAIN_REQUIREMENTS_FILE:-./requirements/security/requirements-security.txt}"
SECURITY_TOOLCHAIN_PYTHON="./artifacts/venv/security/bin/python"
if ! python_interpreter_usable "$SECURITY_TOOLCHAIN_PYTHON"; then
  echo "⚠️ Security toolchain interpreter '${SECURITY_TOOLCHAIN_PYTHON}' is not usable; falling back to python3"
  SECURITY_TOOLCHAIN_PYTHON="python3"
fi

if [[ -f "$SECURITY_TOOLCHAIN_REQUIREMENTS_FILE" ]]; then
  echo && echo "▶ Refreshing security toolchain lockfile installs with ${SECURITY_TOOLCHAIN_PYTHON}"
  "$SECURITY_TOOLCHAIN_PYTHON" -m pip install --require-hashes --force-reinstall -r "$SECURITY_TOOLCHAIN_REQUIREMENTS_FILE" --no-deps
fi

echo && echo "▶ Running security toolchain dependency freshness checks with ${SECURITY_TOOLCHAIN_PYTHON}"
SECURITY_TOOLCHAIN_FRESHNESS_ARGS=(
  ./src/scripts/check_dependency_freshness.py
  --requirements "${SECURITY_TOOLCHAIN_REQUIREMENTS_FILE}"
  --output-json "${REPORT_DIR}/security-toolchain-dependency-freshness.json"
  --output-text "${REPORT_DIR}/security-toolchain-dependency-freshness.txt"
)
#R030: Security toolchain freshness remains a strict gate for actionable/direct drift.
SECURITY_TOOLCHAIN_FRESHNESS_ARGS+=(--fail-on-any-actionable-outdated)
SECURITY_TOOLCHAIN_FRESHNESS_ARGS+=(--fail-on-direct-outdated)
#R032: Security toolchain venv must not include requested packages outside declared lockfile.
SECURITY_TOOLCHAIN_FRESHNESS_ARGS+=(--fail-on-venv-cruft)
"$SECURITY_TOOLCHAIN_PYTHON" "${SECURITY_TOOLCHAIN_FRESHNESS_ARGS[@]}"

#R040: Verify required runtime/security binaries and emit integrity artifacts.
if [[ "$RUN_BINARY_INTEGRITY_CHECK" == "true" ]]; then
  echo && echo "▶ Running binary integrity checks"
  BINARY_INTEGRITY_ARGS=(
    ./src/scripts/check_binary_integrity.py
    --policy "${BINARY_INTEGRITY_POLICY_FILE}"
    --output-json "${REPORT_DIR}/binary-integrity.json"
    --output-text "${REPORT_DIR}/binary-integrity.txt"
    --fail-on-missing-required
    --fail-on-version
    --fail-on-hash
  )
  "$PROJECT_PYTHON" "${BINARY_INTEGRITY_ARGS[@]}"
fi

#R015: Run optional Teller API version freshness checks via machine-readable API metadata.
if [[ "$RUN_TELLER_VERSION_FRESHNESS" == "true" ]]; then
  echo && echo "▶ Running Teller API version freshness checks"
  TELLER_VERSION_ARGS=(
    ./src/scripts/check_teller_api_version_freshness.py
    --output-json "${REPORT_DIR}/teller-api-version-freshness.json"
    --output-text "${REPORT_DIR}/teller-api-version-freshness.txt"
    --version-sources "${TELLER_API_VERSION_SOURCES}"
    --dashboard-url "${TELLER_API_VERSION_DASHBOARD_URL}"
  )
  if command -v 1psa >/dev/null 2>&1 && [[ -n "$TELLER_API_VERSION_DASHBOARD_PSA_ITEM" ]] && 1psa -l "$TELLER_API_VERSION_DASHBOARD_PSA_ITEM" >/dev/null 2>&1; then
    TELLER_VERSION_ARGS+=(--dashboard-psa-item "${TELLER_API_VERSION_DASHBOARD_PSA_ITEM}")
    TELLER_VERSION_ARGS+=(--dashboard-username-field "${TELLER_API_VERSION_DASHBOARD_USERNAME_FIELD}")
    TELLER_VERSION_ARGS+=(--dashboard-password-field "${TELLER_API_VERSION_DASHBOARD_PASSWORD_FIELD}")
    TELLER_VERSION_ARGS+=(--dashboard-otp-field "${TELLER_API_VERSION_DASHBOARD_OTP_FIELD}")
  fi
  if [[ -n "$TELLER_API_BASELINE_VERSION" ]]; then
    TELLER_VERSION_ARGS+=(--baseline-version "${TELLER_API_BASELINE_VERSION}")
  fi
  if [[ "$TELLER_API_VERSION_FAIL_ON_NEW" == "true" ]]; then
    TELLER_VERSION_ARGS+=(--fail-on-new)
  fi
  "$PROJECT_PYTHON" "${TELLER_VERSION_ARGS[@]}"
fi

#R020: Run optional PostgreSQL version freshness checks and emit freshness artifacts.
if [[ "$RUN_POSTGRES_FRESHNESS" == "true" ]]; then
  echo && echo "▶ Running PostgreSQL freshness checks"
  if [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]] && [[ -z "$POSTGRES_SERVER_PSQL_ARGS" ]]; then
    if [[ -n "${POSTGRES_SERVER_DSN:-}" ]]; then
      echo "ℹ️ PostgreSQL server check target: server-dsn (explicit)"
    else
      POSTGRES_SERVER_PSQL_ARGS="-h localhost -U teller -d prod"
      echo "ℹ️ PostgreSQL server check target: psql args (default) '${POSTGRES_SERVER_PSQL_ARGS}'"
    fi
  elif [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]]; then
    echo "ℹ️ PostgreSQL server check target: psql args (explicit) '${POSTGRES_SERVER_PSQL_ARGS}'"
  fi
  if [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]] && [[ -z "${PGPASSWORD:-}" ]] && command -v 1psa >/dev/null 2>&1; then
    if [[ "$POSTGRES_SERVER_PSA_FIELD" == "password" ]]; then
      postgres_password="$(1psa -p "$POSTGRES_SERVER_PSA_ITEM" 2>/dev/null || true)"
      export PGPASSWORD="$postgres_password"
    else
      postgres_password="$(1psa -f "$POSTGRES_SERVER_PSA_ITEM" "$POSTGRES_SERVER_PSA_FIELD" 2>/dev/null || true)"
      export PGPASSWORD="$postgres_password"
    fi
    if [[ -n "${PGPASSWORD:-}" ]]; then
      echo "ℹ️ PostgreSQL password source: 1psa (${POSTGRES_SERVER_PSA_ITEM}:${POSTGRES_SERVER_PSA_FIELD})"
    else
      echo "⚠️ PostgreSQL password source: 1psa lookup returned empty (${POSTGRES_SERVER_PSA_ITEM}:${POSTGRES_SERVER_PSA_FIELD})"
    fi
  elif [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]] && [[ -n "${PGPASSWORD:-}" ]]; then
    echo "ℹ️ PostgreSQL password source: PGPASSWORD environment variable"
  elif [[ "$POSTGRES_CHECK_SERVER_VERSION" == "true" ]]; then
    echo "⚠️ PostgreSQL password source: not set (PGPASSWORD missing and 1psa unavailable)"
  fi
  POSTGRES_FRESHNESS_ARGS=(
    ./src/scripts/check_postgres_freshness.py
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
