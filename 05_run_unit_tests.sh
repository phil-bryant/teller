#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Run tests from repository root regardless of caller working directory.
cd "$SCRIPT_DIR"

# Optional runner controls for local development.
RUN_SHELL_TESTS="${RUN_SHELL_TESTS:-true}"
RUN_PYTHON_TESTS="${RUN_PYTHON_TESTS:-true}"
RUN_SQL_TESTS="${RUN_SQL_TESTS:-true}"
RUN_SWIFT_TESTS="${RUN_SWIFT_TESTS:-true}"
RUN_MACOS_UI_REGRESSION_TESTS="${RUN_MACOS_UI_REGRESSION_TESTS:-false}"
RUN_MACOS_CRASH_REPORTER_SMOKE_TEST="${RUN_MACOS_CRASH_REPORTER_SMOKE_TEST:-false}"
BATS_FILTER="${BATS_FILTER:-}"
SQL_TESTS_DIR="${SQL_TESTS_DIR:-./tests/sql}"
SQL_TEST_DATABASE="${SQL_TEST_DATABASE:-${TELLER_DB_NAME:-${DB_NAME:-prod}}}"
PG_PROVE_BIN="${PG_PROVE_BIN:-}"
DB_HOST="${TELLER_DB_HOST:-localhost}"
DB_PORT="${TELLER_DB_PORT:-5432}"
DB_USER="${TELLER_DB_USER:-teller}"
DB_PASSWORD="${TELLER_DB_PASSWORD:-${DB_PASSWORD:-}}"

#R005: Prefer project venv when available.
if [[ -d "./teller-venv" ]]; then
  # shellcheck disable=SC1091
  source "./teller-venv/bin/activate"
fi

if [[ "$RUN_SHELL_TESTS" == "true" ]]; then
  if [[ -d "./tests/sh" ]]; then
    if ! command -v bats >/dev/null 2>&1; then
      echo "❌ bats is required for shell unit tests. Install bats-core and rerun."
      exit 1
    fi
    echo "▶ Running shell unit tests (bats)..."
    if [[ -n "$BATS_FILTER" ]]; then
      bats --filter "$BATS_FILTER" ./tests/sh
    else
      bats ./tests/sh
    fi
  else
    echo "ℹ️  Skipping shell unit tests: ./tests/sh not found."
  fi
fi

#R010 #R015: Discover all unittest modules and propagate failures.
if [[ "$RUN_PYTHON_TESTS" == "true" ]]; then
  echo "▶ Running Python unit tests (unittest)..."
  python3 -m unittest discover tests/py
fi

#R025 #R015: Run pgTAP SQL unit tests and stop on first failure.
if [[ "$RUN_SQL_TESTS" == "true" ]]; then
  if [[ -d "$SQL_TESTS_DIR" ]]; then
    echo "▶ Preparing SQL unit tests (pgTAP)..."
    if [[ -z "$PG_PROVE_BIN" ]]; then
      if command -v pg_prove >/dev/null 2>&1; then
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
      DB_PASSWORD="$(1psa -p "${TELLER_PSA_ITEM:-localhost_postgres_teller}")"
    fi
    if [[ -z "$DB_PASSWORD" ]]; then
      echo "❌ failed to resolve teller DB password for SQL unit tests."
      exit 1
    fi
    if ! command -v psql >/dev/null 2>&1; then
      echo "❌ psql is required to verify pgTAP extension availability. Install PostgreSQL client tools and rerun."
      exit 1
    fi

    if ! pgtap_installed="$(
      PGPASSWORD="${DB_PASSWORD}" psql -w -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -v ON_ERROR_STOP=1 -d "$SQL_TEST_DATABASE" -Atqc \
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
        if ! PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" \
          PGOPTIONS="-c search_path=teller,public" \
          "$PG_PROVE_BIN" --dbname "$SQL_TEST_DATABASE" "$sql_test_file"; then
          if [[ "$PG_PROVE_BIN" == "${HOME}/perl5/bin/pg_prove" ]]; then
            brew_perl_prefix="$(brew --prefix perl 2>/dev/null || true)"
            if [[ -x "${brew_perl_prefix}/bin/perl" ]]; then
              echo "ℹ️  Retrying user-local pg_prove with Homebrew perl..."
              PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" \
                PGOPTIONS="-c search_path=teller,public" \
                "${brew_perl_prefix}/bin/perl" "$PG_PROVE_BIN" --dbname "$SQL_TEST_DATABASE" "$sql_test_file"
              continue
            fi
          fi
          exit 1
        fi
      done
    fi
  else
    echo "ℹ️  Skipping SQL unit tests: ${SQL_TESTS_DIR} not found."
  fi
fi

#R020 #R015: Run Swift package tests and propagate failures.
if [[ "$RUN_SWIFT_TESTS" == "true" ]]; then
  if [[ -d "./macos-ui/Tests" ]]; then
    if ! command -v swift >/dev/null 2>&1; then
      echo "❌ swift is required for Swift unit tests. Install Xcode command line tools and rerun."
      exit 1
    fi
    echo "▶ Running Swift unit tests (swift test)..."
    #R020: Clear stale SPM build cache to avoid module-cache path mismatches after folder renames.
    rm -rf ./macos-ui/.build
    swift test --package-path ./macos-ui
  else
    echo "ℹ️  Skipping Swift unit tests: ./macos-ui/Tests not found."
  fi
fi

if [[ "$RUN_MACOS_UI_REGRESSION_TESTS" == "true" ]]; then
  echo "▶ Running macOS UI regression test lane..."
  ./06_run_macos_ui_regression_tests.sh
fi

#R030: Allow opt-in PLCrashReporter smoke verification in unit-test orchestration.
if [[ "$RUN_MACOS_CRASH_REPORTER_SMOKE_TEST" == "true" ]]; then
  echo "▶ Running macOS crash reporter smoke test lane..."
  ./17_verify_macos_crash_reporter.sh
fi
