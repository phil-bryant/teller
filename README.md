# teller

Local-first Teller data platform: PostgreSQL schema + ingest scripts + classification API + native macOS review app.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01_install_prerequisites.sh`
  - Ensures Homebrew, required tooling (`shellcheck`, `swiftlint`, `bats`, `gitleaks`, `clamscan`, OWASP ZAP), `1psa`, and sibling repos (`pg_install`, `pgtap`) are present.
  - Ensures Xcode first-launch and license acceptance are completed (using `1psa` for sudo credential input when needed).
- `02_create_venv.sh`
- `03_load_requirements.sh`
- `04_install_classifier_api_tls.sh`
- `tests/t02_run_dependency_freshness_tests.sh`
- `tests/t01_run_av_test.sh`
- `tests/t03_run_static_security_tests.sh`
- `05_deploy_database.sh`
- `tests/t05_deploy_database_verification_test.sh` (includes updated_at trigger coverage verification)
- `tests/t07_run_shell_unit_tests.sh`
- `tests/t08_run_python_unit_tests.sh`
- `tests/t09_run_mutation_tests.sh`
- `tests/t06_run_sql_unit_tests.sh`
- `tests/t11_run_fuzz_tests.sh`
- `tests/t10_run_swift_unit_tests.sh`
- `tests/t14_run_macos_ui_regression_tests.sh` (recommended pre-merge gate)
- `tests/t15_verify_macos_crash_test.sh`
- `tests/t13_run_teller_api_smoke_tests.sh`
- `06_fetch_teller_api_data.py`
- `07_backfill_bank_statements.py`
- `08_run_classification_api.py`
- `08_run_classification_api.py` (compatibility alias)
- `tests/t16_classification_persistence_verification_test.sh`
- `tests/t12_run_dynamic_security_tests.sh`
- `09_run_classification_macos_ui.sh`
- `10_run_all_tests_parallel.sh`
- `11_report_quality_trends.sh`
- `12_validate_quality_target.sh`
- `...` (any future numbered scripts)
- `97_backup_database.sh` (creates timestamped backup + globals)
- `98_destroy_database.sh` (cleanup/teardown)
- `99_restore_database.sh` (restores latest or selected backup)

Do not skip ahead unless you know a later script's dependencies are already satisfied.

## Quick Start

From the project root:

```bash
./01_install_prerequisites.sh
./02_create_venv.sh
source ./teller-venv/bin/activate
./03_load_requirements.sh
./04_install_classifier_api_tls.sh
./tests/t02_run_dependency_freshness_tests.sh
./tests/t01_run_av_test.sh
./tests/t03_run_static_security_tests.sh
mkdir -p config/local
cp config/db-profiles-EXAMPLE.json config/db-profiles.json
# Edit config/db-profiles.json default_profile / 1psa_or_env_item for your environment.
./05_deploy_database.sh
./tests/t05_deploy_database_verification_test.sh
./tests/t07_run_shell_unit_tests.sh
./tests/t08_run_python_unit_tests.sh
./tests/t09_run_mutation_tests.sh
./tests/t06_run_sql_unit_tests.sh
./tests/t11_run_fuzz_tests.sh
./tests/t10_run_swift_unit_tests.sh
./tests/t14_run_macos_ui_regression_tests.sh
./tests/t15_verify_macos_crash_test.sh
./tests/t13_run_teller_api_smoke_tests.sh
./06_fetch_teller_api_data.py
./07_backfill_bank_statements.py
./08_run_classification_api.py
./tests/t16_classification_persistence_verification_test.sh
./tests/t12_run_dynamic_security_tests.sh
./09_run_classification_macos_ui.sh
./10_run_all_tests_parallel.sh
```

Before `./05_deploy_database.sh`, ensure PostgreSQL is installed and running for your selected profile target (for local runs, start your local server/service first).

## Repository Layout

- `src/teller/` - Python package (ORM models, DB profile/engine, ingest persistence, FastAPI classification API, Mailcart proxy client).
- `src/macos-ui/` - SwiftUI desktop app (`TransactionClassifier`) for Match Review, category management, and Connect enrollment flows.
- `src/sql/postgres/` - canonical schema objects, triggers, and views for the `teller` schema.
- `tests/` - `py/` (`unittest`), `sh/` (`bats`), `sql/` (`pgTAP`) plus `macos-ui` snapshot/XCUITest lanes.
- `requirements/` - requirements traceability docs mapped to source `#R...` tags.
- `archive/legacy/` - archived legacy/demo assets (including the retired Teller Connect demo HTML and `teller-connect-ui` sample project).

## Tech Stack Overview

```text
External systems
  - Teller API (api.teller.io)
  - 1psa secret store CLI
  - Mailcart local service (optional)

Python backend layer
  - Runtime: Python 3.10+ (setup prefers 3.12)
  - Frameworks/libs: FastAPI, Starlette, Uvicorn, Pydantic, SQLAlchemy,
    psycopg2-binary, requests, structlog, python-dotenv
  - Main flows:
    * Ingest: 18_fetch_teller_api_data.py
    * Backfill: 19_backfill_bank_statements.py
    * API: 08_run_classification_api.py -> src/teller/teller_classification_api.py

Data/persistence layer
  - PostgreSQL (local or managed profile via db profile config)
  - Schema objects: src/sql/postgres/
  - DB helpers: src/teller/teller_db.py, src/teller/teller_db_profile.py

macOS app/UI layer
  - Swift 5.9, SwiftUI, macOS 14+
  - Package: src/macos-ui/Package.swift
  - App: TransactionClassifier (includes WKWebView Connect + crash reporting)
```

Testing stack:

- Shell lane: `bats` (`tests/sh`)
- Python lane: `unittest` (`tests/py`)
- SQL lane: `pgTAP`/`pg_prove` (`tests/sql`)
- Swift lane: `swift test` (`src/macos-ui/Tests`)
- macOS UI lane: snapshot + XCUITest

Security stack:

- SAST: `semgrep`, `bandit`, `pip-audit`, `detect-secrets`, `gitleaks`, `shellcheck`, `swiftlint`
- DAST: `schemathesis`, OWASP ZAP
- AV: ClamAV

## Testing and Verification

Run these checks from the project root after activating the project virtual environment:

```bash
source ./teller-venv/bin/activate
```

### Local Run Profiles

Use these profiles to keep day-to-day runs fast while preserving a high-confidence full gate before release work.

PR-fast profile (recommended default):

```bash
source ./teller-venv/bin/activate
./tests/t04_run_requirements_traceability_tests.sh
./09_run_shell_unit_tests.sh
./10_run_python_unit_tests.sh
./12_run_sql_unit_tests.sh
./14_run_swift_unit_tests.sh
RUN_XCUITESTS=false ./15_run_macos_ui_regression_tests.sh
```

Full-confidence profile (parallel aggregate gate):

```bash
source ./teller-venv/bin/activate
PARALLEL_CLASSIFIER_API_PORT=8787 \
PARALLEL_DAST_BASE_PORT=8788 \
PARALLEL_DAST_REUSE_EXISTING_API=false \
./24_run_all_tests_parallel.sh
```

Quality trend / target checks:

```bash
./25_report_quality_trends.sh
./26_validate_quality_target.sh
```

Profile notes:

- `25` keeps lanes parallel; API/DAST ports are isolated by default (`8787` vs `8788`) to reduce race-driven flakes.
- Override lane isolation only when intentionally diagnosing a single shared-runtime issue.
- For deeper security/fuzz coverage, combine with nightly-style knobs:
  - `SCHEMATHESIS_MAX_EXAMPLES=100`
  - `FUZZ_MAX_EXAMPLES=500 FUZZ_TIMEOUT_SECONDS=600`
  - `MUTATION_SKIP_PREFLIGHT=false` (now default for strict local full runs)

Security scanning runs via `06_run_static_security_tests.sh` (SAST) and `22_run_dynamic_security_tests.sh` (DAST).
Security policy defaults live under `config/security/` (`semgrep.yml`, `bandit.yml`, `gitleaksignore`) and can be overridden with `SEMGREP_CONFIG_PATH`, `BANDIT_CONFIG_PATH`, and `GITLEAKS_IGNORE_PATH`.
Antivirus scanning runs via `05_run_av_test.sh` (ClamAV lane).
Dependency freshness automation runs via `04_run_dependency_freshness_tests.sh`.

### 1) Requirements Traceability Verification

Verifies every requirement ID in `requirements/**/*-requirements.md` is mapped to matching `#R...` tags in referenced source files.

```bash
./tests/t04_run_requirements_traceability_tests.sh
```

Optional single-pair mode:

```bash
./tests/t04_run_requirements_traceability_tests.sh requirements/22_classification_persistence_verification_test-requirements.md tests/t16_classification_persistence_verification_test.sh
```

### 2) Unit Tests

Runs split unit lanes so each suite can run independently (and in parallel under `25`).

```bash
./09_run_shell_unit_tests.sh
./10_run_python_unit_tests.sh
./12_run_sql_unit_tests.sh
./14_run_swift_unit_tests.sh
```

Equivalent direct Python unittest invocation:

```bash
python3 -m unittest discover tests/py
```

Shell tests (`tests/sh`) run via `bats` in lane `10`. See `tests/sh/README.md` for stubbing conventions and scope boundaries.

Hypothesis and other Python tool caches live under `artifacts/cache/` (not a root-level `.hypothesis/`). Test runners source `src/scripts/export_test_cache_env.sh`; activating `teller-venv` inside this repo does the same via `bin/activate`.

### 2b) Fuzz Tests

Run dedicated property/stateful fuzz tests:

```bash
./13_run_fuzz_tests.sh
```

The fuzz lane defaults to `tests/py/properties` and writes machine-readable telemetry to `artifacts/fuzz/fuzz-summary.json`.

Useful flags:

- `FUZZ_TEST_PATHS=tests/py/properties` (default; path or glob accepted by pytest)
- `FUZZ_MAX_EXAMPLES=500` (default per-property budget)
- `FUZZ_DEADLINE_MS=1000` (default Hypothesis deadline in ms; set `0` to disable)
- `FUZZ_TIMEOUT_SECONDS=300` (default lane timeout)
- `FUZZ_MIN_PROPERTY_TESTS=4` (default minimum collected property tests)
- `FUZZ_MIN_PER_TEST_RATIO_PERCENT=90` (default per-test passing floor percentage)
- `FUZZ_MIN_TOTAL_EXAMPLES=<int>` (default derived from `FUZZ_MIN_PROPERTY_TESTS * FUZZ_MAX_EXAMPLES * FUZZ_MIN_PER_TEST_RATIO_PERCENT / 100`)
- `FUZZ_REPORT_DIR=./artifacts/fuzz` (summary + replay log output root)
- `HYPOTHESIS_STORAGE_DIRECTORY=./artifacts/cache/hypothesis` (example database path)

Recommended profiles:

- PR-fast profile:

```bash
FUZZ_MAX_EXAMPLES=100 FUZZ_TIMEOUT_SECONDS=180 ./13_run_fuzz_tests.sh
```

- Nightly-deep profile:

```bash
FUZZ_MAX_EXAMPLES=500 FUZZ_TIMEOUT_SECONDS=600 ./13_run_fuzz_tests.sh
```

On failure, the lane saves the most recent replayable run log at `artifacts/fuzz/fuzz-failure-last.log`.

### 2c) macOS UI Regression Tests

Runs deterministic snapshot tests and macOS XCUITest smoke flows for `macos-ui`.

This lane can run before full Connect enrollment and before script `19`.

```bash
./15_run_macos_ui_regression_tests.sh
```

Common flags:

- `RUN_SNAPSHOT_TESTS=true|false` (default `true`)
- `SNAPSHOT_RECORD=true|false` (default `false`)
- `RUN_XCUITESTS=true|false` (default `true`)

### 3) Classification Persistence End-to-End Verification

This checks API-to-database persistence by writing one classification via API and reading it back from Postgres.

The verifier auto-starts the API by default if `/health` is unavailable (`CLASSIFICATION_PERSISTENCE_START_API=true`).

1. Start the API in one terminal (optional):

```bash
./08_run_classification_api.py
```

1. Run the verifier:

```bash
./21_classification_persistence_verification_test.sh
```

Strict/CI-style mode requiring explicit IDs:

```bash
TXN_ID=txn_xxx CATEGORY_ID=123 ./21_classification_persistence_verification_test.sh --require-env-ids
```

Mutation endpoints require a write token from the `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` (checked by `08_run_classification_api.py`).

### 4) Built-In Smoke Verifications in Setup Scripts

These checks run as part of existing app/setup workflows:

- `./09_run_classification_macos_ui.sh`
  - Builds and launches the native macOS app; Connect tab owns enrollment add/reconnect/delete and token persistence.
  - Connect setup smoke checks are handled in-app by `TellerSetupService` (`GET /institutions`, and optionally `GET /accounts` when token is present).

### 5) Security Scanning (SAST/DAST)

Security scanners are installed automatically into an isolated `artifacts/venv/security` when you run the security lane (avoids dependency conflicts with the app venv).

Manual install into `artifacts/venv/security` (optional):

```bash
python3 -m venv artifacts/venv/security
./artifacts/venv/security/bin/pip install --upgrade pip
./artifacts/venv/security/bin/pip install -r requirements/security/requirements-security.txt
```

Run the SAST lane:

```bash
./06_run_static_security_tests.sh
```

Run the DAST lane:

```bash
./22_run_dynamic_security_tests.sh
```

Useful flags:

- `RUN_SAST=true|false` (default `true`)
- `RUN_DAST=true|false` (default `true`)
- `RUN_SWIFT_SAST=true|false` (default `true`; runs security-focused SwiftLint rules on first-party `./src/macos-ui` Swift code)
- `RUN_ZAP=true|false` (default `true`, requires local ZAP CLI executable, e.g. `ZAP.sh`)
- `ZAP_HOME_DIR=/path` (default `./artifacts/security/zap-home`; isolates ZAP state per repo to avoid global home-directory lock conflicts)
- `ZAP_QUIET=true|false` (default `false`; when `false`, shows live ZAP quick-scan progress including attack phase output)
- `DAST_REUSE_EXISTING_API=true|false` (default `false`; reuse already-running classification API instead of starting one)
- `SECURITY_FAIL_ON_HIGH_CRITICAL=true|false` (default `true`)
- `RUN_TOKEN_CAPTURE_DAST=true|false|auto` (default `auto`)
- `RUN_SCHEMATHESIS=true|false` (default `true`)
- `SCHEMATHESIS_SEED=424242` (default deterministic seed)
- `SCHEMATHESIS_MAX_EXAMPLES=25` (default API fuzz depth per operation)
- ShellCheck runs automatically in SAST mode and writes `shellcheck.json` into the report directory.

Recommended DAST profiles:

- PR-fast profile:

```bash
RUN_DAST=true RUN_ZAP=false SCHEMATHESIS_MAX_EXAMPLES=10 ./22_run_dynamic_security_tests.sh
```

- Nightly-deep profile:

```bash
RUN_DAST=true RUN_ZAP=true SCHEMATHESIS_MAX_EXAMPLES=100 ./22_run_dynamic_security_tests.sh
```

### 5b) Antivirus Scanning (ClamAV)

Run the dedicated AV lane:

```bash
./05_run_av_test.sh
```

Useful flags:

- `RUN_CLAMAV=true|false` (default `true`; runs recursive ClamAV malware scan on repository files)
- `AV_FAIL_ON_INFECTED=true|false` (default `true`; fails lane when infected files are detected)
- `SECURITY_REPORT_DIR=/path` (default `./artifacts/security/reports`; output root for AV/SAST lane artifacts)
- `CLAMAV_SCAN_TARGET=/path` (default `.`; scan root for ClamAV repository scan)
- `CLAMAV_HEARTBEAT_SECONDS=15` (default `15`; emits periodic "still scanning" status lines during ClamAV scans)
- `CLAMAV_SIGNATURE_MAX_AGE_HOURS=48` (default `48`; freshness threshold for signature age warning output)

ClamAV AV-lane notes:

- The AV script prints the resolved scan target path before scanning.
- It prints signature freshness metadata (latest DB file + age).
- During long scans, it emits periodic heartbeat lines so the run is not silent.
- On first run, if malware signature databases are missing, the script automatically attempts a one-time `freshclam --stdout` update and retries the scan.

For policy and behavior details, see `requirements/06_run_static_security_tests-requirements.md`, `requirements/22_run_dynamic_security_tests-requirements.md`, and `requirements/05_run_av_test-requirements.md`.

### 6) Dependency Freshness + Teller API Smoke

Use separate lanes for dependency/PostgreSQL freshness and Teller API smoke coverage.

Run locally:

```bash
./04_run_dependency_freshness_tests.sh
./17_run_teller_api_smoke_tests.sh
```

Artifacts are written to `./artifacts/security/`:

- `dependency-freshness.json` and `dependency-freshness.txt` (outdated package summary with major/minor/patch classification)
- `teller-api-version-freshness.json` and `teller-api-version-freshness.txt` (best-effort Teller API version metadata freshness check)
- `postgres-freshness.json` and `postgres-freshness.txt` (PostgreSQL client/server freshness status and policy evaluation)
- `teller-api-smoke.json` and `teller-api-smoke.txt` (live Teller smoke checks / fallback compatibility checks)

Useful flags:

- `DEPENDENCY_FAIL_ON_MAJOR=true|false` (default `false`) to fail when major dependency updates are available
- `DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=true|false` (default `true`; direct `requirements.txt` entries gate failure, transitive updates remain informational)
- `RUN_POSTGRES_FRESHNESS=true|false` (default `true`)
- `POSTGRES_MIN_CLIENT_VERSION=x.y` (optional minimum accepted `psql` version)
- `POSTGRES_CHECK_SERVER_VERSION=true|false` (default `true`; runs `SHOW server_version_num`)
- `POSTGRES_MIN_SERVER_VERSION=x.y` (optional minimum accepted server version; used when server checks are enabled)
- `POSTGRES_SERVER_DSN=...` (optional DSN passed to `psql` for server checks)
- `POSTGRES_SERVER_PSQL_ARGS="-h localhost -U teller -d prod"` (optional explicit `psql` args for server checks)
- `POSTGRES_SERVER_PSA_ITEM` / `POSTGRES_SERVER_PSA_FIELD` (defaults `localhost_postgres_teller` / `password`; used to resolve `PGPASSWORD` via `1psa` when needed)
- `POSTGRES_FAIL_ON_STALE=true|false` (default `false`; fail when configured Postgres freshness policy is not met)
- `POSTGRES_CHECK_CVES=true|false` (default `true`; evaluates versions against local CVE snapshot ranges)
- `POSTGRES_FAIL_ON_CVE=true|false` (default `true`; fail when CVE policy is violated)
- `POSTGRES_CVE_POLICY_FILE=/path/to/postgres-cve-policy.json` (default `./config/security/postgres-cve-policy.json`)
- `POSTGRES_CVE_SNAPSHOT_FILE=/path/to/postgres-cve-snapshot.json` (default `./config/security/postgres-cve-snapshot.json`)
- `POSTGRES_REFRESH_CVE_SNAPSHOT=true|false` (default `true`; refreshes CVE snapshot from postgresql.org at runtime)
- `DEPENDENCY_REPORT_DIR=/path` (default `./artifacts/security`)
- `DEPENDENCY_CHECK_PYTHON=/path/to/python` (default `./teller-venv/bin/python` when available)
- `RUN_TELLER_VERSION_FRESHNESS=true|false` (default `true`)
- `TELLER_API_VERSION_SOURCES=url1,url2` (default: `https://teller.io/docs/api,https://api.teller.io/openapi.json,https://api.teller.io/swagger.json`)
- `TELLER_API_BASELINE_VERSION=x.y.z` (optional baseline for update detection)
- `TELLER_API_VERSION_FAIL_ON_NEW=true|false` (default `false`)
- `TELLER_API_VERSION_DASHBOARD_URL=https://teller.io/settings/application` (dashboard page to scrape for app-specific version state)
- `TELLER_API_VERSION_DASHBOARD_PSA_ITEM=TELLER_IO` (1psa item for dashboard login; when present, used before public docs sources)
- `TELLER_API_VERSION_DASHBOARD_USERNAME_FIELD=username` and `TELLER_API_VERSION_DASHBOARD_PASSWORD_FIELD=password`
- `TELLER_API_VERSION_DASHBOARD_OTP_FIELD=one-time password` (optional 1psa TOTP/OTP field forwarded during dashboard login)
- `TELLER_ACCESS_TOKEN=...` (optional for smoke checks; when omitted, smoke checks use local `~/.teller/auth_token*.json` discovery)
- `TELLER_SMOKE_INSTITUTION_ID=<suffix>` (optional; passes `--institution-id` to smoke checks)
- `TELLER_SMOKE_REPORT_DIR=/path` (default `./artifacts/security`)
- `TELLER_SMOKE_TIMEOUT_SECONDS=<int>` (default `15`)

PostgreSQL CVE policy files:

- `./config/security/postgres-cve-policy.json` controls severity threshold and snapshot freshness requirements.
- `./config/security/postgres-cve-snapshot.json` is the local advisory snapshot used by the freshness lane.

Triage expectations:

- Dependency freshness failures: review `dependency-freshness.*` artifacts, validate compatibility, and rerun `./09_run_shell_unit_tests.sh`.
- Teller API version freshness: checks your dashboard-configured app version first (via optional `1psa` credentials) and falls back to public docs/spec metadata; can report `unknown` when sources are unavailable.
- Dependency transitive update warnings: informational by default; refresh the venv (`./03_load_requirements.sh`) when you want to align transitive packages.
- Teller smoke warnings/failures: local token discovery is the default path and authenticated checks run across all discovered local tokens; set `TELLER_ACCESS_TOKEN` only when you want to force one token context.
- PostgreSQL server-version warnings: verify connection target (`POSTGRES_SERVER_PSQL_ARGS` or `POSTGRES_SERVER_DSN`) and password source (`PGPASSWORD` or `1psa`) shown in script output.

## API Reference Docs

Local Teller API reference notes now live under `docs/teller-api-reference/`.

## Secret Sources

`archive/legacy/secrets.txt` is archival context only and is not read by scripts.

Active secret and credential sources are:

- `~/.teller/` files used by Teller workflows:
  - `application_id.txt`
  - `certificate.pem`
  - `private_key.pem`
  - `auth_token.json` and optional `auth_token_<suffix>.json`
  - `enrollment_id.txt` and optional `enrollment_id_<suffix>.txt`
  - `db_profiles.json` (canonical shared DB profile location)
- `1psa` items used by database and setup scripts:
  - `localhost_postgres_postgres` / `localhost_postgres_teller` by default for DB scripts
  - `TELLER_CLASSIFIER_WRITE_TOKEN` for classification API writes
- Environment variables passed to scripts (for example `POSTGRES_PSA_ITEM`, `TELLER_PSA_ITEM`, `TELLER_DB_PROFILE`, `TELLER_DB_PROFILE_FILE`)
- `~/.env` for local runtime settings loaded by `18_fetch_teller_api_data.py`

## What Each Core Script Does

- `01_install_prerequisites.sh`
  - Ensures Homebrew is installed.
  - Ensures required tooling is available (`go`, `git`, `bats`, `swiftlint`, `shellcheck`, `clamscan`, `gitleaks`, `perl`/`cpanm`, OWASP ZAP).
  - Installs `1psa` (from `../1psa`) and clones `pg_install` and `pgtap` siblings.
- `02_create_venv.sh`
  - Creates a Python virtual environment named `<repo>-venv`.
- `03_load_requirements.sh`
  - Installs dependencies from `requirements.txt` (supports optional `requirements-cpu.txt` / `requirements-gpu.txt` if present).
  - Must be run with the project virtual environment active.
- `05_run_av_test.sh`
  - Runs dedicated ClamAV antivirus checks (signature freshness, recursive scan, optional one-time `freshclam` retry, and AV gating).
- `06_run_static_security_tests.sh`
  - Runs local SAST checks (Semgrep, Bandit, pip-audit, gitleaks, detect-secrets, ShellCheck, and SwiftLint for `macos-ui`).
- `09_run_shell_unit_tests.sh`
  - Runs shell (`bats`), Python (`unittest` in `tests/py`), SQL (`pgTAP` via `pg_prove`), and Swift (`swift test`) lanes.
  - Supports lane toggles with `RUN_SHELL_TESTS`, `RUN_PYTHON_TESTS`, `RUN_SQL_TESTS`, and `RUN_SWIFT_TESTS`.
- `07_deploy_database.sh`
  - Creates/configures the `prod` database.
  - Applies SQL schema objects in dependency order from `src/sql/postgres/`.
- `08_deploy_database_verification_test.sh`
  - Verifies required database objects, trigger/FK invariants, and `updated_at` trigger coverage after deploy.
- `15_run_macos_ui_regression_tests.sh`
  - Runs `macos-ui` snapshot regression tests and the macOS XCUITest smoke suite.
  - Supports selective gates with `RUN_SNAPSHOT_TESTS`, `SNAPSHOT_RECORD`, and `RUN_XCUITESTS`.
- `16_verify_macos_crash_test.sh`
  - Validates crash-reporter behavior and expected failure metadata for `macos-ui`.
- `17_run_teller_api_smoke_tests.sh`
  - Runs Teller API smoke checks (`/institutions`, and token-backed `/accounts` / `/identity` when auth resolves).
  - Writes smoke artifacts to `artifacts/security/`.
- `18_fetch_teller_api_data.py`
  - Runs Teller API client operations.
- `19_backfill_bank_statements.py`
  - Backfills statements data.
- `08_run_classification_api.py`
  - Starts local FastAPI service for listing transactions/categories and saving user SNW classifications.
  - Requires `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` before serving.
- `21_classification_persistence_verification_test.sh`
  - End-to-end check: writes one classification via API then confirms DB persistence.
  - Smart default auto-selects `TXN_ID` and `CATEGORY_ID`; use `--require-env-ids` for strict CI mode.
- `22_run_dynamic_security_tests.sh`
  - Runs DAST checks (Schemathesis + OWASP ZAP quick scan and related hardening checks) against running/local API targets.
- `09_run_classification_macos_ui.sh`
  - Builds and launches `src/macos-ui/.build/debug/TransactionClassifier` from the repo root.
  - Connect tab hosts native Teller Connect enrollment/reconnect/add/delete (WebView-backed, no standalone localhost server).
- `24_run_all_tests_parallel.sh`
  - Runs local parallel quality/security gate lanes and aggregates reports under `artifacts/parallel/`.
  - Includes traceability, dependency freshness, Teller smoke checks, AV, SAST, DB verify, unit tests, UI regression, crash reporter, and classification persistence checks.
  - Inherits caller environment for child lanes, so fuzz profile knobs (`FUZZ_*`, `SCHEMATHESIS_*`, `RUN_ZAP`) can be set once before invoking `25`.
- `97_backup_database.sh`
  - Creates a timestamped PostgreSQL custom-format dump in `./backups`.
  - Also captures matching cluster globals (roles/grants) for reliable restores.
- `98_destroy_database.sh`
  - Destroys `prod` database and related roles after explicit confirmation.
- `99_restore_database.sh`
  - Restores latest backup by default (or accepts `--from /path/to/backup.dump`).
  - Exits if `teller` schema already exists in `prod`.
  - Restores matching globals before database objects.

### Operations Recovery Flow (`97` -> `98` -> `99`)

Use this flow to avoid destructive misuse of backup/destroy/restore scripts:

```text
normal operations
      |
      v
97_backup_database.sh
      |
      +--> verify <db>_<timestamp>.dump + matching _globals.sql exist
      |
      v
optional destructive teardown?
      |
      +--> no  -> continue to restore preflight
      |
      +--> yes -> 98_destroy_database.sh
                 |
                 +--> profile selection: TELLER_DB_PROFILE override -> db_profiles default_profile
                 +--> local target: drop DB + roles
                 +--> managed target: drop schema + roles (no DROP DATABASE)
                 +--> confirmation gate: must type "destroy"
      |
      v
99_restore_database.sh
      |
      +--> full restore preflight: if teller schema exists, restore is refused
      +--> table-scoped restore: pass --table schema.table_name to restore specific tables
      +--> restore order: globals first -> dump -> teller password reset/verification
      |
      v
post-restore verification
      |
      +--> ./08_deploy_database_verification_test.sh
      +--> ./21_classification_persistence_verification_test.sh
```

Credential source resolution order used by recovery scripts:

- `97_backup_database.sh`:
  - `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD` (defaults: `localhost_postgres_postgres` / `password`)
- `98_destroy_database.sh`:
  - profile resolution: `TELLER_DB_PROFILE` env override, otherwise profile file `default_profile`
  - managed target credential source: env override first, then profile `PG_ONEPSA_ITEM` via `1psa`
  - local target credential source: `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD` via `1psa`
- `99_restore_database.sh`:
  - admin restore actions: `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD`
  - teller post-restore credential check/reset: `TELLER_PSA_ITEM`/`TELLER_PSA_FIELD`

## Ingest + Normalization + Persistence

### Sequence (`18_fetch_teller_api_data.py`)

Why this flow matters: it makes reruns safe and clarifies where idempotency is enforced before data lands in Postgres.

```text
[scheduler/manual]
      |
      v
18_fetch_teller_api_data.py
      |
      +--> fetch institutions/accounts/transactions (+ balances/identity per account)
      |
      +--> normalize/transform
      |      - pagination merge for full history
      |      - canonicalize duplicate transaction IDs (prefer posted over pending)
      |
      +--> upsert via SQLAlchemy helper layer (src/teller/teller_persist.py)
      |      - account/institution/identity/account-identity upserts
      |      - transaction + transaction-links + transaction-details upserts
      |      - balances upserts
      |      - stale pending transaction reconciliation + orphan relation pruning
      |      - single commit boundary at end of persist_all(...)
      |
      v
PostgreSQL (teller schema)
      |
      +--> views/triggers/audit paths
             - updated_at triggers (create_triggers.sql)
             - row-change audit triggers (create_audit.sql)
             - downstream views (for example teller.transaction_info_view)
```

Idempotency points for repeat runs:

- API fetch can be rerun without duplicate DB rows because persistence uses conflict-aware upserts keyed by stable IDs.
- Duplicate transaction snapshots from Teller are canonicalized so posted versions win deterministically.
- Missing pending transactions are pruned per account to keep local state aligned with current API truth.
- Unreferenced transaction relation rows are pruned after reconciliation to avoid stale graph buildup.
- `persist_all(...)` commits once at the end and the caller rolls back on failure, preserving atomicity per run.

## Configuring Teller Credentials And Connect

Teller dashboard actions and Connect enrollment are partly manual by design.

Manual dashboard/setup prerequisites:

- Sign in to the Teller Dashboard and confirm your application exists.
- Copy your Application ID from [Application Settings](https://teller.io/settings/application).
- Ensure you have an active Teller client certificate/private key pair.
  - If missing/compromised, revoke and reissue in [Certificates](https://teller.io/settings/certificates).

Local app-based enrollment and token refresh:

After completing Teller Connect in the native app, the returned token is saved under `~/.teller`:

```bash
./09_run_classification_macos_ui.sh
```

Connect behavior:

- Open the **Connect** tab to add, reconnect, or delete local enrollment contexts.
- Successful Connect writes `auth_token*.json` and `enrollment_id*.txt` with restrictive permissions.
- Local setup checks for Teller connectivity are available via in-app setup/smoke actions backed by `TellerSetupService`.
- `18_fetch_teller_api_data.py` now launches the macOS app for repair workflows when disconnected enrollments are detected.

Quality/security aggregate checks are available through:

```bash
./24_run_all_tests_parallel.sh
```

## 1psa Items Used by Database Scripts

`07_deploy_database.sh`, `97_backup_database.sh`, `98_destroy_database.sh`, and `99_restore_database.sh` read credentials from `1psa`.

Default items/fields:

- Postgres admin password:
  - item: `localhost_postgres_postgres`
  - field: `password`
- Teller user password:
  - item: `localhost_postgres_teller`
  - field: `password`

Optional overrides:

- `POSTGRES_PSA_ITEM`
- `POSTGRES_PSA_FIELD`
- `TELLER_PSA_ITEM`
- `TELLER_PSA_FIELD`

Example:

```bash
POSTGRES_PSA_ITEM=my_postgres_admin TELLER_PSA_ITEM=my_teller_user ./07_deploy_database.sh
```

## Troubleshooting

- `field 'localhost_postgres_postgres' not found in item ...`
  - Cause: wrong field name was requested.
  - Fix: use `password` field (default), or set `POSTGRES_PSA_FIELD=password`.
- `1psa is required but was not found on PATH`
  - Cause: `1psa` is not installed or not in shell `PATH`.
  - Fix: rerun `./01_install_prerequisites.sh`, then open a new shell.
- `Failed to read postgres password from 1psa item ...`
  - Cause: item name is wrong, inaccessible, or missing `password` field.
  - Fix: verify with `1psa -l localhost_postgres_postgres` and `1psa -p localhost_postgres_postgres`.
- `Failed to read teller password from 1psa item ...`
  - Cause: teller item is wrong or missing `password`.
  - Fix: verify with `1psa -l localhost_postgres_teller` and `1psa -p localhost_postgres_teller`.
- `psql: ... password authentication failed for user ...`
  - Cause: stored credential does not match the database user password.
  - Fix: update the corresponding `1psa` item, then rerun `./07_deploy_database.sh`.
- `could not connect to server on socket ...`
  - Cause: PostgreSQL is not running or listening on expected host/socket.
  - Fix: start PostgreSQL (for example via Homebrew service) and retry.

## Architecture

Detailed system and data-flow documentation now lives in `Architecture.md`.

