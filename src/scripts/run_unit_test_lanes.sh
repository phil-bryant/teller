#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
#R001: Run tests from repository root regardless of caller working directory.
cd "$REPO_ROOT"

#R038: Keep Hypothesis and other Python tool caches out of the repository root.
# shellcheck disable=SC1091
source "${REPO_ROOT}/src/scripts/export_test_cache_env.sh"
export_test_cache_env "$REPO_ROOT"

# Optional runner controls for local development.
RUN_SHELL_TESTS="${RUN_SHELL_TESTS:-true}"
RUN_PYTHON_TESTS="${RUN_PYTHON_TESTS:-true}"
RUN_SQL_TESTS="${RUN_SQL_TESTS:-true}"
RUN_SWIFT_TESTS="${RUN_SWIFT_TESTS:-true}"
RUN_MACOS_UI_REGRESSION_TESTS="${RUN_MACOS_UI_REGRESSION_TESTS:-false}"
MACOS_UI_SWIFTPM_LOCK="${MACOS_UI_SWIFTPM_LOCK:-./src/macos-ui/.swiftpm-run.lock}"
MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS="${MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS:-600}"
#R030: Keep crash-reporter verification isolated to dedicated script 14.
BATS_FILTER="${BATS_FILTER:-}"
SQL_TESTS_DIR="${SQL_TESTS_DIR:-}"

#R025: Resolve DB connection settings from the active profile (1psa+~/.env via the helper).
DB_PROFILE_HELPER="${REPO_ROOT}/src/scripts/db_profile_export.sh"
PG_HOST=""
PG_PORT=""
PG_DBNAME=""
PG_USER=""
PG_SSLMODE="disable"
PG_ONEPSA_ITEM=""
if [[ ! -x "$DB_PROFILE_HELPER" ]]; then
  echo "❌ DB profile helper is missing or not executable: ${DB_PROFILE_HELPER}"
  exit 1
fi
load_profile_exports_from_file() {
  #R025: Load and validate DB profile export lines.
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
    echo "❌ Refusing to load unexpected profile export lines:"
    printf '%s\n' "$invalid_lines"
    return 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$exports_file"
  set +a
}

resolve_sqlcipher_key_from_profile() {
  #R025: Resolve SQLCipher key through profile helper.
  "$DB_PROFILE_HELPER" --print-sqlcipher-key
}

profile_exports_file="$(mktemp)"
if ! "$DB_PROFILE_HELPER" >"$profile_exports_file"; then
  #R035: Refuse SQL lane preflight when DB profile setup is missing.
  rm -f "$profile_exports_file"
  exit 1
fi
if ! load_profile_exports_from_file "$profile_exports_file"; then
  rm -f "$profile_exports_file"
  exit 1
fi
rm -f "$profile_exports_file"

SQL_TEST_DATABASE="${SQL_TEST_DATABASE:-${TELLER_DB_NAME:-${PG_DBNAME:-}}}"
PG_PROVE_BIN="${PG_PROVE_BIN:-}"
DB_HOST="${TELLER_DB_HOST:-${PG_HOST:-localhost}}"
DB_PORT="${TELLER_DB_PORT:-${PG_PORT:-5432}}"
DB_USER="${TELLER_DB_USER:-${PG_USER:-teller}}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-${DB_PASSWORD:-}}"
DB_DIALECT="${DB_DIALECT:-postgresql}"
SQLITE_PATH="${TELLER_DB_SQLITE_PATH:-${SQLITE_PATH:-}}"
SQLCIPHER_KEY="${TELLER_DB_SQLCIPHER_KEY:-}"
if [[ -z "$SQL_TESTS_DIR" ]]; then
  if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
    SQL_TESTS_DIR="./tests/sql/sqlite"
  else
    SQL_TESTS_DIR="./tests/sql"
  fi
fi

python_interpreter_usable() {
  #R001: Validate candidate Python interpreter usability.
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" -c "import site" >/dev/null 2>&1
}

resolve_bats_jobs() {
  #R001: Resolve bounded Bats parallel job count.
  local default_jobs cap
  default_jobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"
  if [[ "${PARALLEL_LANES:-1}" =~ ^[0-9]+$ ]] && [[ "${PARALLEL_LANES:-1}" -gt 1 ]]; then
    default_jobs=$(( default_jobs / PARALLEL_LANES ))
    if [[ "$default_jobs" -lt 1 ]]; then
      default_jobs=1
    fi
  fi
  BATS_JOBS_RESOLVED="${BATS_JOBS:-$default_jobs}"
  cap="${BATS_JOBS_CAP:-8}"
  if [[ "$cap" =~ ^[0-9]+$ ]] && [[ "$cap" -gt 0 ]] && [[ "$BATS_JOBS_RESOLVED" -gt "$cap" ]]; then
    BATS_JOBS_RESOLVED="$cap"
  fi
}

run_single_bats_file() {
  #R015: Run one Bats file and propagate failures.
  local bats_file="$1"
  local -a bats_env_unsets=(
    -u TELLER_DB_PASSWORD
    -u DB_PASSWORD
    -u DB_DIALECT
    -u PROFILE_NAME
    -u PROFILE_TARGET
    -u PG_HOST
    -u PG_PORT
    -u PG_DBNAME
    -u PG_USER
    -u PG_SSLMODE
    -u PG_SEARCH_PATH
    -u PG_RUNTIME_ROLE
    -u PG_ONEPSA_ITEM
    -u SQLITE_PATH
    -u SQLCIPHER_KEY
    -u TELLER_DB_HOST
    -u TELLER_DB_PORT
    -u TELLER_DB_NAME
    -u TELLER_DB_USER
    -u TELLER_DB_SQLITE_PATH
    -u TELLER_DB_SQLCIPHER_KEY
  )
  if [[ -n "$BATS_FILTER" ]]; then
    env "${bats_env_unsets[@]}" bats --filter "$BATS_FILTER" "$bats_file"
  else
    env "${bats_env_unsets[@]}" bats "$bats_file"
  fi
}

swiftpm_state_looks_stale() {
  #R020: Detect stale SwiftPM checkout state errors.
  local output_text="$1"
  [[ "$output_text" == *"cannot be accessed"* && "$output_text" == *".build/"* ]] && return 0
  [[ "$output_text" == *"was compiled with module cache path"* ]] && return 0
  [[ "$output_text" == *"is defined in both"* && "$output_text" == *"ModuleCache"* ]] && return 0
  return 1
}

clear_conflicting_swiftpm_build_dirs() {
  #R020: Clear conflicting SwiftPM build directories.
  local output_text="$1"
  local cache_roots=""
  cache_roots="$(
    python3 - <<'PY' "$output_text"
import re
import sys

text = sys.argv[1]
roots = sorted(set(re.findall(r"(/[^'\s]+/src/macos-ui)/\.build", text)))
for root in roots:
    print(root)
PY
  )"
  if [[ -n "$cache_roots" ]]; then
    while IFS= read -r cache_root; do
      [[ -n "$cache_root" ]] || continue
      if [[ -d "$cache_root/.build" ]]; then
        rm -rf "$cache_root/.build"
      fi
    done <<< "$cache_roots"
  fi
  rm -rf ./src/macos-ui/.build
}

#R005: Prefer project venv when available.
if [[ -d "./teller-venv" ]] && [[ -f "./teller-venv/bin/activate" ]]; then
  if ! python_interpreter_usable "./teller-venv/bin/python"; then
    echo "⚠️  Skipping teller-venv activation because its interpreter is not usable."
  else
  # shellcheck disable=SC1091
    source "./teller-venv/bin/activate"
  fi
fi

if [[ "$RUN_SHELL_TESTS" == "true" ]]; then
  if [[ -d "./tests/sh" ]]; then
    if ! command -v bats >/dev/null 2>&1; then
      echo "❌ bats is required for shell unit tests. Install bats-core and rerun."
      exit 1
    fi
    shopt -s nullglob
    bats_files=(./tests/sh/*.bats)
    shopt -u nullglob
    if [[ "${#bats_files[@]}" -eq 0 ]]; then
      echo "ℹ️  Skipping shell unit tests: no *.bats files found in ./tests/sh."
    else
      resolve_bats_jobs
      if [[ "$BATS_JOBS_RESOLVED" -le 1 || "${#bats_files[@]}" -le 1 ]]; then
        echo "▶ Running shell unit tests (bats, serial)..."
        for bats_file in "${bats_files[@]}"; do
          run_single_bats_file "$bats_file"
        done
      else
        echo "▶ Running shell unit tests (bats, parallel by file; jobs=${BATS_JOBS_RESOLVED})..."
        printf '%s\0' "${bats_files[@]}" | \
          BATS_FILTER="$BATS_FILTER" \
          xargs -0 -P "$BATS_JOBS_RESOLVED" -I {} bash -c '
            set -euo pipefail
            file="$1"
            bats_env_unsets=(
              -u TELLER_DB_PASSWORD
              -u DB_PASSWORD
              -u DB_DIALECT
              -u PROFILE_NAME
              -u PROFILE_TARGET
              -u PG_HOST
              -u PG_PORT
              -u PG_DBNAME
              -u PG_USER
              -u PG_SSLMODE
              -u PG_SEARCH_PATH
              -u PG_RUNTIME_ROLE
              -u PG_ONEPSA_ITEM
              -u SQLITE_PATH
              -u SQLCIPHER_KEY
              -u TELLER_DB_HOST
              -u TELLER_DB_PORT
              -u TELLER_DB_NAME
              -u TELLER_DB_USER
              -u TELLER_DB_SQLITE_PATH
              -u TELLER_DB_SQLCIPHER_KEY
            )
            if [[ -n "${BATS_FILTER:-}" ]]; then
              env "${bats_env_unsets[@]}" bats --filter "$BATS_FILTER" "$file"
            else
              env "${bats_env_unsets[@]}" bats "$file"
            fi
          ' _ {}
      fi
    fi
  else
    echo "ℹ️  Skipping shell unit tests: ./tests/sh not found."
  fi
fi

#R010: Run Python unit lane through pytest as the single runner semantic.
#R015: Propagate python-suite failures.
if [[ "$RUN_PYTHON_TESTS" == "true" ]]; then
  echo "▶ Running Python unit tests (pytest)..."
  UNITTEST_PYTHON="python3"
  if [[ -n "${PYTHONPATH:-}" ]]; then
    UNITTEST_PYTHONPATH="./src:${PYTHONPATH}"
  else
    UNITTEST_PYTHONPATH="./src"
  fi
  if python_interpreter_usable "./teller-venv/bin/python3"; then
    UNITTEST_PYTHON="./teller-venv/bin/python3"
  elif [[ -d "./teller-venv/lib" ]]; then
    python_minor_version="$(python3 - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
    preferred_site_packages_dir="./teller-venv/lib/python${python_minor_version}/site-packages"
    if [[ -d "$preferred_site_packages_dir" ]]; then
      preferred_site_packages_dir_abs="$(cd "$preferred_site_packages_dir" && pwd)"
      if [[ -n "$UNITTEST_PYTHONPATH" ]]; then
        UNITTEST_PYTHONPATH="${preferred_site_packages_dir_abs}:${UNITTEST_PYTHONPATH}"
      else
        UNITTEST_PYTHONPATH="${preferred_site_packages_dir_abs}"
      fi
    fi
  fi
  PYTHONPATH="$UNITTEST_PYTHONPATH" "$UNITTEST_PYTHON" -m pytest tests/py -q
fi

#R025: Run pgTAP SQL unit tests.
#R015: Stop SQL suite on first failure.
if [[ "$RUN_SQL_TESTS" == "true" ]]; then
  if [[ -d "$SQL_TESTS_DIR" ]]; then
    if [[ "$DB_DIALECT" == "sqlite" || "${PROFILE_TARGET:-local}" == "sqlite" ]]; then
      if [[ -z "$SQLITE_PATH" ]]; then
        echo "❌ SQLite SQL lane requires SQLITE_PATH from profile export."
        exit 1
      fi
      if [[ -z "$SQLCIPHER_KEY" ]]; then
        if ! SQLCIPHER_KEY="$(resolve_sqlcipher_key_from_profile)"; then
          echo "❌ SQLite SQL lane could not resolve SQLCipher key from profile helper."
          exit 1
        fi
      fi
      if [[ -z "$SQLCIPHER_KEY" ]]; then
        echo "❌ SQLite SQL lane requires SQLCIPHER_KEY via TELLER_DB_SQLCIPHER_KEY or profile sqlcipher_key."
        exit 1
      fi
      if ! command -v sqlcipher >/dev/null 2>&1; then
        echo "❌ sqlcipher is required for SQLite SQL unit tests."
        exit 1
      fi
      shopt -s nullglob
      sql_test_files=("$SQL_TESTS_DIR"/*.sql)
      shopt -u nullglob
      if [[ "${#sql_test_files[@]}" -eq 0 ]]; then
        echo "ℹ️  Skipping SQL unit tests: no *.sql files found in ${SQL_TESTS_DIR}."
      else
        echo "▶ Running SQL unit tests (sqlcipher)..."
        SQLITE_ESCAPED_KEY="$(printf "%s" "$SQLCIPHER_KEY" | sed "s/'/''/g")"
        for sql_test_file in "${sql_test_files[@]}"; do
          sqlcipher "$SQLITE_PATH" <<SQL
.bail on
PRAGMA key='${SQLITE_ESCAPED_KEY}';
.read "${sql_test_file}"
SQL
        done
      fi
    else
    echo "▶ Preparing SQL unit tests (pgTAP)..."
    if [[ -z "$PG_PROVE_BIN" ]]; then
      if [[ -x "/opt/homebrew/bin/pg_prove" ]]; then
        PG_PROVE_BIN="/opt/homebrew/bin/pg_prove"
      elif [[ -x "/usr/local/bin/pg_prove" ]]; then
        PG_PROVE_BIN="/usr/local/bin/pg_prove"
      elif command -v pg_prove >/dev/null 2>&1; then
        PG_PROVE_BIN="$(command -v pg_prove)"
      elif [[ -x "${HOME}/perl5/bin/pg_prove" ]]; then
        PG_PROVE_BIN="${HOME}/perl5/bin/pg_prove"
      fi
    fi
    if [[ -z "$PG_PROVE_BIN" ]]; then
      echo "❌ pg_prove is required for pgTAP SQL unit tests. Install pgTAP tools and rerun."
      exit 1
    fi
    if [[ -z "$DB_PASSWORD" ]]; then
      if ! command -v 1psa >/dev/null 2>&1; then
        echo "❌ TELLER_DB_PASSWORD is unset and 1psa is unavailable for fallback lookup."
        exit 1
      fi
      DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-${PG_ONEPSA_ITEM:-localhost_postgres_teller}}")"
    fi
    if [[ -z "$DB_PASSWORD" ]]; then
      echo "❌ failed to resolve teller DB password for SQL unit tests."
      exit 1
    fi
    # Some local DB profiles run SQL tests as restricted roles; pgTAP helper
    # objects require elevated privileges. Prefer postgres role when available.
    if [[ "${SQL_TESTS_USE_ADMIN_ROLE:-true}" == "true" && "$DB_USER" != "postgres" ]]; then
      admin_password="${POSTGRES_ADMIN_PASSWORD:-}"
      if [[ -z "$admin_password" ]] && command -v 1psa >/dev/null 2>&1; then
        admin_password="$(1psa -p "${POSTGRES_PSA_ITEM:-localhost_postgres_postgres}" 2>/dev/null || true)"
      fi
      if [[ -n "$admin_password" ]]; then
        echo "ℹ️  Using postgres admin role for pgTAP execution."
        DB_USER="postgres"
        DB_PASSWORD="$admin_password"
      fi
    fi
    if [[ -z "$SQL_TEST_DATABASE" ]]; then
      echo "❌ Resolved profile is missing PG_DBNAME and SQL_TEST_DATABASE/TELLER_DB_NAME are unset."
      exit 1
    fi
    if ! command -v psql >/dev/null 2>&1; then
      echo "❌ psql is required to verify pgTAP extension availability. Install PostgreSQL client tools and rerun."
      exit 1
    fi

    if ! pgtap_installed="$(
      PGPASSWORD="${DB_PASSWORD}" PGSSLMODE="${PG_SSLMODE:-disable}" psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -v ON_ERROR_STOP=1 -d "$SQL_TEST_DATABASE" -Atqc \
        "SELECT 1 FROM pg_extension WHERE extname = 'pgtap' LIMIT 1;" 2>&1
    )"; then
      echo "❌ failed to query '${SQL_TEST_DATABASE}' for pgtap extension availability."
      echo "$pgtap_installed"
      exit 1
    fi

    if [[ "$pgtap_installed" != "1" ]]; then
      echo "❌ pgtap extension is required in database '${SQL_TEST_DATABASE}'. Run: CREATE EXTENSION pgtap;"
      exit 1
    fi

    shopt -s nullglob
    sql_test_files=("$SQL_TESTS_DIR"/*.sql)
    shopt -u nullglob

    if [[ "${#sql_test_files[@]}" -eq 0 ]]; then
      echo "ℹ️  Skipping SQL unit tests: no *.sql files found in ${SQL_TESTS_DIR}."
    else
      echo "▶ Running SQL unit tests (pgTAP via pg_prove)..."
      for sql_test_file in "${sql_test_files[@]}"; do
        if ! PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${PG_SSLMODE:-disable}" \
          PGOPTIONS="-c search_path=public,teller" \
          "$PG_PROVE_BIN" --dbname "$SQL_TEST_DATABASE" "$sql_test_file"; then
          if [[ "$PG_PROVE_BIN" == "${HOME}/perl5/bin/pg_prove" ]]; then
            brew_perl_bin="/opt/homebrew/bin/perl"
            if [[ ! -x "$brew_perl_bin" ]]; then
              brew_perl_prefix="$(brew --prefix perl 2>/dev/null || true)"
              if [[ -n "$brew_perl_prefix" ]]; then
                brew_perl_bin="${brew_perl_prefix}/bin/perl"
              fi
            fi
            if [[ -x "$brew_perl_bin" ]]; then
              echo "ℹ️  Retrying user-local pg_prove with Homebrew perl..."
              PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGSSLMODE="${PG_SSLMODE:-disable}" \
                PGOPTIONS="-c search_path=public,teller" \
                "$brew_perl_bin" "$PG_PROVE_BIN" --dbname "$SQL_TEST_DATABASE" "$sql_test_file"
              continue
            fi
          fi
          exit 1
        fi
      done
    fi
    fi
  else
    echo "ℹ️  Skipping SQL unit tests: ${SQL_TESTS_DIR} not found."
  fi
fi

#R020: Run Swift lane with bounded stale-cache retry recovery.
#R015: Propagate Swift suite failures by exiting on non-zero status.
if [[ "$RUN_SWIFT_TESTS" == "true" ]]; then
  if [[ -d "./src/macos-ui/Tests" ]]; then
    if ! command -v swift >/dev/null 2>&1; then
      echo "❌ swift is required for Swift unit tests. Install Xcode command line tools and rerun."
      exit 1
    fi
    echo "▶ Running Swift unit tests (swift test)..."
    MACOS_UI_SWIFT_LOCK_HELPER="./src/scripts/macos_ui_swift_lock.sh"
    if [[ ! -f "$MACOS_UI_SWIFT_LOCK_HELPER" ]]; then
      echo "❌ macOS UI SwiftPM lock helper not found at ${MACOS_UI_SWIFT_LOCK_HELPER}."
      exit 1
    fi
    # shellcheck disable=SC1090
    source "$MACOS_UI_SWIFT_LOCK_HELPER"
    run_swift_tests_with_lock() {
      #R010: Run Swift tests under shared lock with retry policy.
      macos_ui_with_swiftpm_lock "$MACOS_UI_SWIFTPM_LOCK" "$MACOS_UI_SWIFT_LOCK_TIMEOUT_SECONDS" "run_unit_test_lanes:swift-test" \
        swift test --package-path ./src/macos-ui 2>&1
    }
    set +e
    swift_test_output="$(run_swift_tests_with_lock)"
    swift_test_exit=$?
    set -e
    printf '%s\n' "$swift_test_output"
    if [[ "$swift_test_exit" -ne 0 ]]; then
      if [[ "$swift_test_output" == *"sandbox_apply: Operation not permitted"* ]]; then
        echo "⚠️  Skipping Swift unit tests in restricted runtime (swift sandbox apply permission denied)."
      elif swiftpm_state_looks_stale "$swift_test_output"; then
        #R020: Recover only on stale-cache/moved-worktree style errors instead of deleting .build preemptively.
        echo "ℹ️  Detected stale SwiftPM cache state; clearing ./src/macos-ui/.build and retrying swift test once..."
        if ! clear_conflicting_swiftpm_build_dirs "$swift_test_output"; then
          echo "⚠️  Unable to fully clear ./src/macos-ui/.build in restricted runtime; continuing with original failure."
          exit "$swift_test_exit"
        fi
        set +e
        swift_test_output="$(run_swift_tests_with_lock)"
        swift_test_exit=$?
        set -e
        printf '%s\n' "$swift_test_output"
        if [[ "$swift_test_exit" -ne 0 ]]; then
          exit "$swift_test_exit"
        fi
      else
        exit "$swift_test_exit"
      fi
    fi
  else
    echo "ℹ️  Skipping Swift unit tests: ./src/macos-ui/Tests not found."
  fi
fi

if [[ "$RUN_MACOS_UI_REGRESSION_TESTS" == "true" ]]; then
  echo "▶ Running macOS UI regression test lane..."
  ./tests/t14_run_macos_ui_regression_tests.sh
fi
