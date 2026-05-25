# teller

Local-first Teller data platform: PostgreSQL schema + ingest scripts + classification API + native macOS review app.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01_install_prerequisites.sh`
  - Ensures Homebrew, required tooling (`shellcheck`, `swiftlint`, `bats`, `gitleaks`, `clamscan`, OWASP ZAP), `1psa`, and sibling repos (`pg_install`, `pgtap`) are present.
  - Ensures Xcode first-launch and license acceptance are completed (using `1psa` for sudo credential input when needed).
- `02_create_venv.sh`
- `03_load_requirements.sh`
- `04_run_dependency_freshness_tests.sh`
- `05_run_av_test.sh`
- `06_run_static_security_tests.sh`
- `07_deploy_database.sh`
- `08_deploy_database_verification_test.sh` (includes updated_at trigger coverage verification)
- `09_run_shell_unit_tests.sh`
- `10_run_python_unit_tests.sh`
- `11_run_mutation_tests.sh`
- `12_run_sql_unit_tests.sh`
- `13_run_fuzz_tests.sh`
- `14_run_swift_unit_tests.sh`
- `15_run_macos_ui_regression_tests.sh` (recommended pre-merge gate)
- `16_verify_macos_crash_test.sh`
- `17_run_teller_api_smoke_tests.sh`
- `18_fetch_teller_api_data.py`
- `19_backfill_bank_statements.py`
- `20_run_classification_api.py`
- `21_classification_persistence_verification_test.sh`
- `22_run_dynamic_security_tests.sh`
- `23_run_classification_macos-ui.sh`
- `24_run_all_tests_parallel.sh`
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
./04_run_dependency_freshness_tests.sh
./05_run_av_test.sh
./06_run_static_security_tests.sh
cp db-profiles-EXAMPLE.json db-profiles.json
# Edit db-profiles.json default_profile / 1psa_or_env_item for your environment.
./07_deploy_database.sh
./08_deploy_database_verification_test.sh
./09_run_shell_unit_tests.sh
./10_run_python_unit_tests.sh
./11_run_mutation_tests.sh
./12_run_sql_unit_tests.sh
./13_run_fuzz_tests.sh
./14_run_swift_unit_tests.sh
./15_run_macos_ui_regression_tests.sh
./16_verify_macos_crash_test.sh
./17_run_teller_api_smoke_tests.sh
./18_fetch_teller_api_data.py
./19_backfill_bank_statements.py
./20_run_classification_api.py
./21_classification_persistence_verification_test.sh
./22_run_dynamic_security_tests.sh
./23_run_classification_macos-ui.sh
./24_run_all_tests_parallel.sh
```

Before `./07_deploy_database.sh`, ensure PostgreSQL is installed and running for your selected profile target (for local runs, start your local server/service first).

## Repository Layout

- `teller/` - Python package (ORM models, DB profile/engine, ingest persistence, FastAPI classification API, Mailcart proxy client).
- `macos-ui/` - SwiftUI desktop app (`TransactionClassifier`) for Match Review, category management, and Connect enrollment flows.
- `sql/postgres/` - canonical schema objects, triggers, and views for the `teller` schema.
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
  - Runtime: Python 3.8+ (setup prefers 3.12)
  - Frameworks/libs: FastAPI, Starlette, Uvicorn, Pydantic, SQLAlchemy,
    psycopg2-binary, requests, structlog, python-dotenv
  - Main flows:
    * Ingest: 18_fetch_teller_api_data.py
    * Backfill: 19_backfill_bank_statements.py
    * API: 20_run_classification_api.py -> teller/teller_classification_api.py

Data/persistence layer
  - PostgreSQL (local or managed profile via db profile config)
  - Schema objects: sql/postgres/
  - DB helpers: teller/teller_db.py, teller/teller_db_profile.py

macOS app/UI layer
  - Swift 5.9, SwiftUI, macOS 14+
  - Package: macos-ui/Package.swift
  - App: TransactionClassifier (includes WKWebView Connect + crash reporting)
```

Testing stack:

- Shell lane: `bats` (`tests/sh`)
- Python lane: `unittest` (`tests/py`)
- SQL lane: `pgTAP`/`pg_prove` (`tests/sql`)
- Swift lane: `swift test` (`macos-ui/Tests`)
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

Security scanning runs via `06_run_static_security_tests.sh` (SAST) and `22_run_dynamic_security_tests.sh` (DAST).
Security policy defaults live under `config/security/` (`semgrep.yml`, `bandit.yml`, `gitleaksignore`) and can be overridden with `SEMGREP_CONFIG_PATH`, `BANDIT_CONFIG_PATH`, and `GITLEAKS_IGNORE_PATH`.
Antivirus scanning runs via `05_run_av_test.sh` (ClamAV lane).
Dependency freshness automation runs via `04_run_dependency_freshness_tests.sh`.

### 1) Requirements Traceability Verification

Verifies every requirement ID in `requirements/**/*-requirements.md` is mapped to matching `#R...` tags in referenced source files.

```bash
./00_run_requirements_traceability_tests.sh
```

Optional single-pair mode:

```bash
./00_run_requirements_traceability_tests.sh requirements/21_classification_persistence_verification_test-requirements.md 21_classification_persistence_verification_test.sh
```

### 2) Unit Tests

Runs split unit lanes so each suite can run independently (and in parallel under `22`).

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

Shell tests (`tests/sh`) run via `bats` in lane `09`. See `tests/sh/README.md` for stubbing conventions and scope boundaries.

### 2b) macOS UI Regression Tests

Runs deterministic snapshot tests and macOS XCUITest smoke flows for `macos-ui`.

This lane can run before full Connect enrollment and before script `18`.

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
./20_run_classification_api.py
```

1. Run the verifier:

```bash
./21_classification_persistence_verification_test.sh
```

Strict/CI-style mode requiring explicit IDs:

```bash
TXN_ID=txn_xxx CATEGORY_ID=123 ./21_classification_persistence_verification_test.sh --require-env-ids
```

Mutation endpoints require a write token from the `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` (checked by `20_run_classification_api.py`).

### 4) Built-In Smoke Verifications in Setup Scripts

These checks run as part of existing app/setup workflows:

- `./23_run_classification_macos-ui.sh`
  - Builds and launches the native macOS app; Connect tab owns enrollment add/reconnect/delete and token persistence.
  - Connect setup smoke checks are handled in-app by `TellerSetupService` (`GET /institutions`, and optionally `GET /accounts` when token is present).

### 5) Security Scanning (SAST/DAST)

Security scanners are installed automatically into an isolated `.security-venv` when you run the security lane (avoids dependency conflicts with the app venv).

Manual install into `.security-venv` (optional):

```bash
python3 -m venv .security-venv
./.security-venv/bin/pip install --upgrade pip
./.security-venv/bin/pip install -r requirements-security.txt
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
- `RUN_SWIFT_SAST=true|false` (default `true`; runs security-focused SwiftLint rules on first-party `./macos-ui` Swift code)
- `RUN_ZAP=true|false` (default `true`, requires local ZAP CLI executable, e.g. `ZAP.sh`)
- `ZAP_HOME_DIR=/path` (default `${SECURITY_REPORT_DIR:-./.security-reports}/zap-home`; isolates ZAP state per repo to avoid global home-directory lock conflicts)
- `ZAP_QUIET=true|false` (default `false`; when `false`, shows live ZAP quick-scan progress including attack phase output)
- `DAST_REUSE_EXISTING_API=true|false` (default `false`; reuse already-running classification API instead of starting one)
- `SECURITY_FAIL_ON_HIGH_CRITICAL=true|false` (default `true`)
- `RUN_TOKEN_CAPTURE_DAST=true|false|auto` (default `auto`)
- ShellCheck runs automatically in SAST mode and writes `shellcheck.json` into the report directory.

### 5b) Antivirus Scanning (ClamAV)

Run the dedicated AV lane:

```bash
./05_run_av_test.sh
```

Useful flags:

- `RUN_CLAMAV=true|false` (default `true`; runs recursive ClamAV malware scan on repository files)
- `AV_FAIL_ON_INFECTED=true|false` (default `true`; fails lane when infected files are detected)
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

Artifacts are written to `./.security-reports/`:

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
- `POSTGRES_CVE_POLICY_FILE=/path/to/postgres-cve-policy.json` (default `./security/postgres-cve-policy.json`)
- `POSTGRES_CVE_SNAPSHOT_FILE=/path/to/postgres-cve-snapshot.json` (default `./security/postgres-cve-snapshot.json`)
- `POSTGRES_REFRESH_CVE_SNAPSHOT=true|false` (default `true`; refreshes CVE snapshot from postgresql.org at runtime)
- `DEPENDENCY_REPORT_DIR=/path` (default `./.security-reports`)
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
- `TELLER_SMOKE_REPORT_DIR=/path` (default `./.security-reports`)
- `TELLER_SMOKE_TIMEOUT_SECONDS=<int>` (default `15`)

PostgreSQL CVE policy files:

- `./security/postgres-cve-policy.json` controls severity threshold and snapshot freshness requirements.
- `./security/postgres-cve-snapshot.json` is the local advisory snapshot used by the freshness lane.

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
  - Applies SQL schema objects in dependency order from `sql/postgres/`.
- `08_deploy_database_verification_test.sh`
  - Verifies required database objects, trigger/FK invariants, and `updated_at` trigger coverage after deploy.
- `15_run_macos_ui_regression_tests.sh`
  - Runs `macos-ui` snapshot regression tests and the macOS XCUITest smoke suite.
  - Supports selective gates with `RUN_SNAPSHOT_TESTS`, `SNAPSHOT_RECORD`, and `RUN_XCUITESTS`.
- `16_verify_macos_crash_test.sh`
  - Validates crash-reporter behavior and expected failure metadata for `macos-ui`.
- `17_run_teller_api_smoke_tests.sh`
  - Runs Teller API smoke checks (`/institutions`, and token-backed `/accounts` / `/identity` when auth resolves).
  - Writes smoke artifacts to `.security-reports/`.
- `18_fetch_teller_api_data.py`
  - Runs Teller API client operations.
- `19_backfill_bank_statements.py`
  - Backfills statements data.
- `20_run_classification_api.py`
  - Starts local FastAPI service for listing transactions/categories and saving user SNW classifications.
  - Requires `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` before serving.
- `21_classification_persistence_verification_test.sh`
  - End-to-end check: writes one classification via API then confirms DB persistence.
  - Smart default auto-selects `TXN_ID` and `CATEGORY_ID`; use `--require-env-ids` for strict CI mode.
- `22_run_dynamic_security_tests.sh`
  - Runs DAST checks (Schemathesis + OWASP ZAP quick scan and related hardening checks) against running/local API targets.
- `23_run_classification_macos-ui.sh`
  - Builds and launches `macos-ui/.build/debug/TransactionClassifier` from the repo root.
  - Connect tab hosts native Teller Connect enrollment/reconnect/add/delete (WebView-backed, no standalone localhost server).
- `24_run_all_tests_parallel.sh`
  - Runs local parallel quality/security gate lanes and aggregates reports under `.parallel-checks-reports/`.
  - Includes traceability, dependency freshness, Teller smoke checks, AV, SAST, DB verify, unit tests, UI regression, crash reporter, and classification persistence checks.
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
      +--> upsert via SQLAlchemy helper layer (teller/teller_persist.py)
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
./23_run_classification_macos-ui.sh
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

## GLOBAL ARCHITECTURE: TELLER → MATCHY ← MAILCART

Implemented in this repository: Teller ingest + schema + classification API + macOS review app.
External ecosystem services: Matchy worker/orchestration and Mailcart Outlook/Graph adapter.

```text
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                          SYSTEM LANDSCAPE                                         │
│                                                                                                   │
│  ┌────────────────────────────────┐    HTTP (search/move)     ┌────────────────────────────────┐  │
│  │             MATCHY             │ ────────────────────────► │            MAILCART            │  │
│  │                                │ ◄──────────────────────── │                                │  │
│  │ - FastAPI service              │      message candidates   │ - Outlook/Graph integration    │  │
│  │ - Runs transaction↔email match │                           │ - Search endpoint for emails   │  │
│  │ - Combines scoring + AI ranker │                           │ - Move endpoint to folder      │  │
│  │ - Writes run/candidate/match   │                           │   `matchy`                     │  │
│  │   records to Teller DB         │                           └────────────────────────────────┘  │
│  └───────────────┬────────────────┘                                                               │
│                  │ SQL read/write                                                                 │
│                  ▼                                                                                │
│  ┌──────────────────────────────────────────────────────────┐                                     │
│  │                      TELLER DB                           │                                     │
│  │                                                          │                                     │
│  │ - Source transactions: `teller.transaction`              │                                     │
│  │ - Match run table: `teller.transaction_email_match_run`  │                                     │
│  │ - Candidates table: `teller.transaction_email_candidate` │                                     │
│  │ - Match table: `teller.transaction_email_match`          │                                     │
│  └──────────────────────────────────────────────────────────┘                                     │
│                                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘

TRIGGER FLOW
┌─────────────────────────────┐      POST /v1/matchy/runs       ┌────────────────────────────┐
│ Caller (manual/auto/retry)  │───────────────────────────────► │ Matchy API                 │
│ (operator/job in ecosystem) │                                 │ validates ids + starts run │
└─────────────────────────────┘                                 └────────────────────────────┘
```

### Additional Architecture Views

#### Auth + Token Lifecycle (Connect -> storage -> API usage)

```text
Trust boundaries:
- Local app boundary: macOS SwiftUI app + WKWebView connect surface
- Local secrets-at-rest boundary: ~/.teller (0700 dir, 0400 secret files)
- External API boundary: api.teller.io (mTLS + token auth)

SwiftUI Connect flow
  -> receives token/enrollment callback
  -> writes auth_token*.json + enrollment_id*.txt under ~/.teller
  -> ingest/runtime reads cert/key + per-context token
  -> calls api.teller.io endpoints
  -> on enrollment.disconnected, launch local repair flow and retry once
```

Token lifecycle notes:

- Initial connect/add writes token and enrollment ID files to `~/.teller`.
- Reconnect rotates token in-place for the selected context.
- Multi-context enrollments use suffixed file pairs (`auth_token_<suffix>.json`, `enrollment_id_<suffix>.txt`).
- Certificate/private key rotation remains managed in Teller Dashboard; local scripts only consume local files.

#### Classification Write Path + AuthZ Boundary

```text
macOS UI action
  -> POST /v1/transactions/classifications
  -> FastAPI app startup resolves TELLER_CLASSIFIER_WRITE_TOKEN from 1psa
  -> _require_write_access enforces X-Teller-Write-Token on mutation routes
  -> Pydantic validates payload
  -> SQLAlchemy persists to teller.transaction_nys_snw_category
  -> 21_classification_persistence_verification_test.sh confirms API->DB write/read
```

#### Local Runtime Topology (processes, ports, configs)

```text
TransactionClassifier (SwiftUI app, launched by 23_run_classification_macos-ui.sh)
  -> talks to FastAPI at TELLER_CLASSIFIER_API_URL (default http://127.0.0.1:8787)

20_run_classification_api.py (FastAPI)
  -> binds TELLER_CLASSIFIER_API_HOST/PORT (default 127.0.0.1:8787)
  -> requires 1psa-backed TELLER_CLASSIFIER_WRITE_TOKEN for mutation startup gate
  -> persists via SQLAlchemy to profile-resolved PostgreSQL target

Optional Mailcart proxy target defaults to http://127.0.0.1:8788
  (override with MAILCART_SERVICE_BASE_URL / MAILCART_SERVICE_TOKEN)

Config and secrets:
  - ~/.teller/auth_token*.json, enrollment_id*.txt, certificate.pem, private_key.pem
  - db profile resolution: ~/.teller/db_profiles.json -> ./db-profiles.local.json -> ./db-profiles.json
  - ~/.env fallbacks for ITEM.field profile entries
```

### Teller ↔ Mailcart contract (Match Review UI)

The Teller classifier API proxies Mailcart for the macOS Match Review three-pane UI. The
contract Mailcart exposes (see `mailcart/scripts/matchy_mailcart_api.py` and matchy's
`matchy/mailcart_client.py`):

- `GET /v1/messages/search?query=<string>&limit=<int>` — returns
`{"messages": [{"message_id", "subject", "preview", "received_at", "sender", "body_text"}]}`.
- `GET /v1/messages/{message_id}` — returns
`{"message_id", "subject", "preview", "received_at", "sender", "recipients", "html_body", "text_body", "body_text"}`.
- `POST /v1/messages/{message_id}/move` — used by matchy, not by Teller.

Teller calls Mailcart via the proxy module `teller/teller_mailcart_client.py`:

- Base URL defaults to `http://127.0.0.1:8788` (Mailcart is a local-only service); override
with the `MAILCART_SERVICE_BASE_URL` environment variable (the same name matchy uses).
- Bearer token is optional and read from `MAILCART_SERVICE_TOKEN`; it is only attached when
set. Mailcart does not validate it. The Microsoft Graph token Mailcart uses internally is
managed by Mailcart itself (cached at `~/.cache/mailcart/graph_oauth.json`, refreshed on 401).
- Teller exposes three read-only proxy/aggregation endpoints (no write token required):
`GET /v1/matchy/transactions/{transaction_id}/candidates`,
`GET /v1/matchy/messages/{email_message_id}`,
`GET /v1/matchy/messages/search`. Each endpoint maps Mailcart's
`{message_id, sender, preview, body_text}` fields onto the UI-facing
`{email_message_id, from, snippet, html_body, text_body}` shape used by `MatchCandidateRow`,
`EmailMessage`, and `EmailSearchHit`.
- Per-id Mailcart failures during candidate enrichment degrade gracefully — the row returns
with `mailcart_error` rather than failing the whole listing — so the review pane remains
usable when Mailcart is partially unavailable.

## Teller Technology Stack

```text
TELLER TECH STACK (repo: /Users/phil/local/src/teller)
=======================================================

                              ┌──────────────────────────────────────┐
                              │          EXTERNAL SYSTEMS            │
                              ├──────────────────────────────────────┤
                              │ - Teller API (api.teller.io)         │
                              │ - 1psa secret store CLI              │
                              │ - Mailcart local service (optional)  │
                              └──────────────────┬───────────────────┘
                                                 |
                                                 v
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                            PYTHON BACKEND LAYER                              │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ Runtime: Python 3.8+ (venv; prefers 3.12 in setup script)                    │
 │ Frameworks/Libs: FastAPI, Starlette, Uvicorn, Pydantic, SQLAlchemy,          │
 │                  psycopg2-binary, requests, structlog, python-dotenv         │
 │ Main flows:                                                                  │
 │   - Ingest: 18_fetch_teller_api_data.py                                      │
 │   - Backfill: 19_backfill_bank_statements.py                                 │
 │   - API: 20_run_classification_api.py -> teller/teller_classification_api.py │
 └───────────────────────────────┬──────────────────────────────────────────────┘
                                 |
                                 v
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                         DATA / PERSISTENCE LAYER                         │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ PostgreSQL (local profile or managed profile via db profiles)            │
 │ Schema + SQL objects in: sql/postgres/                                   │
 │ DB helpers in: teller/teller_db.py, teller/teller_db_profile.py          │
 └───────────────────────────────┬──────────────────────────────────────────┘
                                 ^
                                 |
 ┌───────────────────────────────┬──────────────────────────────────────────┐
 │                         MACOS APP / UI LAYER                             │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ Swift 5.9, SwiftUI, macOS 14+                                            │
 │ Package: macos-ui/Package.swift                                          │
 │ App: TransactionClassifier                                               │
 │ Includes WKWebView Connect flows + PLCrashReporter                       │
 └──────────────────────────────────────────────────────────────────────────┘


AUTOMATION AND OPERATIONS
=========================

┌──────────────────────────────────────────────────────────────────────────┐
│ Numbered workflow scripts (project root)                                 │
├──────────────────────────────────────────────────────────────────────────┤
│ 01-03 setup (prereqs, venv, dependencies)                                │
│ 04-06 quality/security prereqs (freshness, AV, SAST)                     │
│ 07-08 DB deploy + verification                                           │
│ 09-13 unit/regression test lanes                                         │
│ 14-21 integration, API smoke, crash verification, app run                │
│ 22 parallel aggregate runner                                             │
│ 97-99 backup / destroy / restore database                                │
└──────────────────────────────────────────────────────────────────────────┘


TESTING STACK
=============

  Shell lane      : bats            (tests/sh)
  Python lane     : unittest        (tests/py)
  SQL lane        : pgTAP/pg_prove  (tests/sql)
  Swift lane      : swift test      (macos-ui/Tests)
  macOS UI lane   : snapshot + XCUITest


SECURITY STACK
==============

  SAST: semgrep, bandit, pip-audit, detect-secrets, gitleaks, shellcheck, swiftlint
  DAST: schemathesis, OWASP ZAP
  AV  : ClamAV


HIGH-LEVEL FLOW
===============

  Teller API --> Python ingest/backfill --> PostgreSQL <--> FastAPI classification API <--> SwiftUI macOS app
                           ^                      ^
                           |                      |
                        1psa secrets         SQL schema + tests


INGEST + NORMALIZATION + PERSISTENCE (SCRIPT 16)
================================================

[scheduler/manual]
      |
      v
18_fetch_teller_api_data.py
      |
      +--> fetch institutions/accounts/transactions
      +--> normalize/transform (pagination + duplicate transaction canonicalization)
      +--> upsert via SQLAlchemy helper layer (persist_all)
      |      - conflict-aware upserts on stable IDs
      |      - stale pending reconciliation + orphan relation pruning
      |      - single commit boundary for atomic persistence
      v
PostgreSQL (teller schema)
      |
      +--> views/triggers/audit paths
```

## Teller Internal Architecture

```text
1) AUTH + TOKEN LIFECYCLE (CONNECT -> STORAGE -> API USAGE)
------------------------------------------------------------
Why: Clarifies security boundaries and where credentials/tokens live and rotate.

```text
Trust boundaries:
- Local app boundary: macOS SwiftUI app + WKWebView connect surface.
- Local secret-at-rest boundary: ~/.teller (0700 dir, 0400 secret files).
- External API boundary: api.teller.io (mTLS + token auth).

┌────────────────────────────────────────────────────────────────────────────────────┐
│                          Local host (macOS machine)                                │
│                                                                                    │
│  1) Connect session bootstrap                                                      │
│  ┌──────────────────────────────────┐       app_id + env + optional enrollment_id  │
│  │ SwiftUI app (ConnectViewModel)  │ -------------------------------------------┐  │
│  │ ConnectAPIClient.startSession   │                                            │  │
│  └──────────────────────────────────┘                                           │  │
│                                                                                 v  │
│  ┌─────────────────────────────────────────────────────────┐  callback(token, id)  │
│  │ Teller Connect JS in WKWebView (ConnectWebFlowView)    │ --------------------┐  │
│  └─────────────────────────────────────────────────────────┘                    │  │
│                                                                                 v  │
│  2) Token/enrollment persistence                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ ~/.teller/                                                                   │  │
│  │ - auth_token.json + enrollment_id.txt (default context)                      │  │
│  │ - auth_token_<suffix>.json + enrollment_id_<suffix>.txt (Add contexts)       │  │
│  │ - certificate.pem + private_key.pem + application_id.txt                     │  │
│  │ - perms: directory 0700, secret files 0400                                   │  │
│  └───────────────────────────────┬──────────────────────────────────────────────┘  │
│                                  │ read contexts + cert/key + token                │
│                                  v                                                 │
│  3) API usage path                                                 4) disconnected │
│  ┌──────────────────────────────────────────────────────────────┐     enrollment   │
│  │ 18_fetch_teller_api_data.py                                  │                  │
│  │ - builds contexts from default/suffix/metadata files         │ ----repair---┐   │
│  │ - sends cert/key (mTLS) + token (basic user token:blank)     │              │   │
│  │ - retries once after local repair workflow                   │              │   │
│  └───────────────────────────────┬──────────────────────────────┘              │   │
└──────────────────────────────────┼─────────────────────────────────────────────┼───┘
                                   │                                             │
                                   v                                             │
                         ┌───────────────────────────────┐                       │
                         │ api.teller.io                 │                       │
                         │ /institutions, /accounts, ... │                       │
                         └───────────────┬───────────────┘                       │
                                         │ enrollment.disconnected               │
                                         └───────────────────────────────────────┘
                                                        launches 23_run_classification_macos-ui.sh
```

Token and credential lifecycle notes:
- Initial connect/add: token returned by Connect is written to `auth_token*.json`; enrollment id is written to matching `enrollment_id*.txt`.
- Reconnect/rotate token: reconnect action updates the selected existing context files in place.
- Multi-context support: add action allocates unique suffixed file pairs so multiple enrollments can coexist.
- Runtime consumption: `18_fetch_teller_api_data.py` reads local contexts, then calls Teller with local cert/key plus per-context token.
- Disconnected enrollment recovery: when Teller returns `enrollment.disconnected`, script triggers the macOS Connect repair flow and retries once.
- Cert/key rotation boundary: certificate/private key issuance and revocation happen in Teller dashboard; local app/scripts only read local `certificate.pem` / `private_key.pem`.


2) INGEST + NORMALIZATION + PERSISTENCE SEQUENCE
-------------------------------------------------
Why: Shows exact order and idempotency points for data movement into Postgres.

[scheduler/manual]
      |
      v
18_fetch_teller_api_data.py
      |
      +--> fetch institutions/accounts/transactions
      |
      +--> normalize/transform
      |
      +--> upsert via SQLAlchemy
      |
      v
PostgreSQL (teller schema)
      |
      +--> views/triggers/audit paths


3) CLASSIFICATION WRITE PATH + AUTHZ BOUNDARY
----------------------------------------------
Why: Makes mutation protection and persistence verification explicit.

```text
Trust/authz boundaries:
- UI boundary: macOS client can invoke read + write routes on localhost FastAPI.
- Mutation boundary: write routes require `X-Teller-Write-Token` that matches 1psa-backed secret.
- Persistence boundary: only validated writes reach Postgres via SQLAlchemy session.

┌──────────────────────────────────────────────────────────────────────────────┐
│ Local host (macOS)                                                           │
│                                                                              │
│ User action in macOS UI (TransactionClassifier/APIClient)                    │
│         │                                                                    │
│         │  GET /v1/transactions (read path; no write-token required)         │
│         ├───────────────────────────────────────────────────────────────┐    │
│         │                                                               │    │
│         │  POST /v1/transactions/classifications (write path)           │    │
│         v                                                               │    │
│  ┌────────────────────────────────────────────────────────────────────┐ │    │
│  │ FastAPI app (`20_run_classification_api.py` -> `create_app`)       │ │    │
│  │                                                                    │ │    │
│  │ 1) Startup preflight: resolve `TELLER_CLASSIFIER_WRITE_TOKEN`      │ │    │
│  │    from 1psa before serving mutation traffic.                      │ │    │
│  │ 2) Request authz: `_require_write_access` enforces                 │ │    │
│  │    `X-Teller-Write-Token` on mutating endpoints only.              │ │    │
│  │ 3) Input validation: Pydantic models (`ClassificationBatchRequest`,│ │    │
│  │    `ClassificationMutation`) reject malformed payloads.            │ │    │
│  │ 4) Persistence: `_write_one` performs SQLAlchemy-backed            │ │    │
│  │    update/insert/delete in `teller.transaction_nys_snw_category`.  │ │    │
│  └───────────────────────────────────────┬────────────────────────────┘ │    │
│                                          │                              │    │
└──────────────────────────────────────────┼──────────────────────────────┼────┘
                                           │                              │
                                           v                              │
                                ┌────────────────────────────────┐        │
                                │ PostgreSQL (teller schema)     │        │
                                │ classification row is persisted│        │
                                └───────────────┬────────────────┘        │
                                                │                         │
                                                └── verified by           │
                                                   `21_classification_persistence_verification_test.sh`
```


4) DATA MODEL ER DIAGRAM (CORE TABLES + RELATIONSHIPS)
-------------------------------------------------------
Why: Repo has rich SQL under `sql/postgres/`; a compact ER view speeds onboarding.

```text
Legend:
- [W] write-heavy (ingest/classification frequently mutates rows)
- [R] read-heavy  (primarily lookup/query workload)
- [M] mixed
- PK/FK only shown in each box

                            ┌─────────────────────────────────────────┐
                            │ teller.institution [R]                  │
                            │ PK institution_id                       │
                            └─────────────────────────────────────────┘
                                               ^
                                               | FK account.institution_id
                            ┌─────────────────────────────────────────┐
                            │ teller.account [W]                      │
                            │ PK account_id                           │
                            │ FK institution_id -> institution.id     │
                            │ enrollment_id (logical; no local FK)    │
                            └─────────────────────────────────────────┘
                                               ^
                                               | FK transaction.account_id
                            ┌─────────────────────────────────────────┐
                            │ teller.transaction [W]                  │
                            │ PK transaction_id                       │
                            │ FK account_id -> account.id             │
                            └─────────────────────────────────────────┘
                                  ^                  ^                ^
                                  |                  |                |
                                  |                  |                +-----------------------------------+
                                  |                  |                                                    |
                                  |                  +-----------------------------------+                |
                                  |                                                      |                |
┌─────────────────────────────────────────┐                          ┌─────────────────────────────────────────┐
│ teller.nys_snw_category [R]             │                          │ teller.transaction_email_match [W]      │
│ PK nys_snw_category_id                  │                          │ PK match_id                             │
└─────────────────────────────────────────┘                          │ FK transaction_id -> transaction.id     │
               ^                                                     └─────────────────────────────────────────┘
               | FK transaction_nys_snw_category.nys_snw_category_id             ^
               |                                                                 | FK transaction_email_match_audit.match_id
┌─────────────────────────────────────────┐                          ┌─────────────────────────────────────────┐
│ teller.transaction_nys_snw_category [W] │                          │ teller.transaction_email_match_audit [W]│
│ PK/FK transaction_id -> transaction.id  │                          │ PK match_audit_id                       │
│ FK nys_snw_category_id -> category.id   │                          │ FK match_id -> email_match.id           │
└─────────────────────────────────────────┘                          └─────────────────────────────────────────┘
                                  ^
                                  | FK transaction_email_match_run.transaction_id
┌─────────────────────────────────────────┐
│ teller.transaction_email_match_run [W]  │
│ PK match_run_id                         │
│ FK transaction_id -> transaction.id     │
└─────────────────────────────────────────┘
               ^
               | FK transaction_email_candidate.match_run_id
┌─────────────────────────────────────────┐
│ teller.transaction_email_candidate [W]  │
│ PK candidate_id                         │
│ FK match_run_id -> match_run.id         │
│ FK transaction_id -> transaction.id     │
└─────────────────────────────────────────┘
               ^
               | FK transaction_email_candidate.transaction_id
               +-----------------------------------------------> teller.transaction.transaction_id
```

FK direction map (child -> parent):
- `account.institution_id -> institution.institution_id`
- `transaction.account_id -> account.account_id`
- `transaction_nys_snw_category.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_nys_snw_category.nys_snw_category_id -> nys_snw_category.nys_snw_category_id`
- `transaction_email_match_run.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_email_candidate.match_run_id -> transaction_email_match_run.match_run_id` (ON DELETE CASCADE)
- `transaction_email_candidate.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_email_match.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_email_match_audit.match_id -> transaction_email_match.match_id` (ON DELETE CASCADE)

Notes:
- `enrollment` is currently modeled as `account.enrollment_id` (no `teller.enrollment` table in `sql/postgres/`).
- `transaction_classification` is implemented as `teller.transaction_nys_snw_category`.
- Matchy tables (`transaction_email_match_run`, `transaction_email_candidate`, `transaction_email_match`, `transaction_email_match_audit`) are in active use by the classification API.


5) LOCAL RUNTIME TOPOLOGY (PROCESSES, PORTS, FILES, ENV)
---------------------------------------------------------
Why: Helpful for debugging "what should be running" and "where config comes from".

```text
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   Local machine (macOS)                                    │
│                                                                                            │
│  App/UI process                                                                            │
│  ┌──────────────────────────────────────────────────────────┐                              │
│  │ SwiftUI app: TransactionClassifier                       │                              │
│  │ launcher: 23_run_classification_macos-ui.sh              │                              │
│  │ Connect runs in-process (no localhost Connect server)    │                              │
│  └───────────────────────────────┬──────────────────────────┘                              │
│                                  │ HTTP: TELLER_CLASSIFIER_API_URL                         │
│                                  │ default http://127.0.0.1:8787                           │
│                                  v                                                         │
│  API process                     ┌───────────────────────────────────────────────────────┐ │
│  ┌───────────────────────────────│ FastAPI: 20_run_classification_api.py                 │ │
│  │                               │ bind env: TELLER_CLASSIFIER_API_HOST/PORT             │ │
│  │                               │ defaults: 127.0.0.1:8787                              │ │
│  │                               │ startup gate: requires 1psa item                      │ │
│  │                               │ TELLER_CLASSIFIER_WRITE_TOKEN                         │ │
│  │                               └───────────────────────┬───────────────────────────────┘ │
│  │                                                       │ SQLAlchemy                      │
│  │                                                       v                                 │
│  │                                 ┌─────────────────────────────────────────────────────┐ │
│  │                                 │ PostgreSQL (profile-resolved)                       │ │
│  │                                 │ typical local target: localhost:5432                │ │
│  │                                 │ selected via TELLER_DB_PROFILE / profile file       │ │
│  │                                 └─────────────────────────────────────────────────────┘ │
│  │                                                                                         │
│  │ optional Mailcart integration                                                           │
│  └──────────────────────────────────────► http://127.0.0.1:8788 (default)                  │
│                                         env: MAILCART_SERVICE_BASE_URL / TOKEN             │
│                                                                                            │
│  File/config + secret sources                                                              │
│  - ~/.teller/auth_token*.json, enrollment_id*.txt, certificate.pem, private_key.pem        │
│  - DB profile file search: ~/.teller/db_profiles.json -> ./db-profiles.local.json ->       │
│    ./db-profiles.json (or TELLER_DB_PROFILE_FILE override)                                 │
│  - ~/.env (loaded by ingest/profile fallback paths for ITEM.field entries)                 │
│  - Secret authority: 1psa (classifier write token + DB connection fields/password)         │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

Local runtime debugging checklist:
- If UI cannot load data, verify FastAPI is listening on `127.0.0.1:8787` (or your `TELLER_CLASSIFIER_API_URL` override).
- If write endpoints fail at startup, verify `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN` returns a non-empty value.
- If DB connect fails, inspect the resolved profile (`TELLER_DB_PROFILE`, profile file path precedence, and `1psa_or_env_item`).
- If match-review email fetch fails, verify optional Mailcart process on `127.0.0.1:8788` or override `MAILCART_SERVICE_BASE_URL`.


6) TEST STRATEGY MAP (LANES -> SCOPE -> GATES)
-----------------------------------------------
Why: Explains why there are many numbered scripts and what each gate protects.

Gate map (left = execution lane, right = protection intent):
- 01-08 setup/deploy checks  -> env/bootstrap/deploy preconditions before deeper validation
- 09 shell tests             -> script behavior/contracts (flags, outputs, failure semantics)
- 10 python tests            -> package/unit behavior for Python ingestion/API helpers
- 11 sql tests               -> schema invariants and DB contract checks (pgTAP)
- 12 swift tests             -> app unit behavior in the macOS client
- 13 ui regression           -> snapshot + XCUITest flow stability
- 14 crash verify            -> crash reporter path and expected crash-handling telemetry
- 15 smoke                   -> external API assumptions and minimal end-to-end liveliness
- 19 persistence e2e         -> API -> DB correctness for write/read persistence paths
- 20 dynamic security        -> runtime attack surface checks (DAST-style probes)
- 22 parallel                -> aggregate readiness signal across gates

How to interpret failures:
- 01-08 fail: stop early; developer/runtime prerequisites are not trustworthy yet.
- 09-14 fail: lane-specific regression in shell/python/sql/swift/ui/crash behavior.
- 15 fail: likely upstream/external contract drift or availability issue.
- 19 fail: persistence contract break between API and database layers.
- 20 fail: potential exploitable runtime behavior; treat as security triage.
- 22 fail: composite readiness not met; inspect failing child lanes.


7) SECURITY THREAT MODEL (TRUST BOUNDARIES + DATA FLOWS)
---------------------------------------------------------
Why: Security tools are present, but a visual threat model explains risk ownership.

```text
Trust boundaries:
- B1 local host boundary (developer macOS runtime)
- B2 external API boundary (Teller api.teller.io)
- B3 secrets boundary (1psa process + ~/.teller secret files)
- B4 DB boundary (PostgreSQL role/session + teller schema)

Legend:
- [TB] trust-boundary crossing
- [AS] attack-surface node

                                       [B2 external API boundary]
                                ┌──────────────────────────────────────┐
                                │ Teller API (mTLS + token auth)       │
                                │ - /institutions /accounts /...       │
                                └───────────────────┬──────────────────┘
                                                    │ F4 response data
                                                    │ + disconnection signals [TB]
                                                    │
┌───────────────────────────────────────────────────┼───────────────────────────────────────────┐
│ [B1 local host boundary]                          │                                           │
│                                                   │                                           │
│  [AS] WKWebView Connect surface                   │                                           │
│  ┌────────────────────────────────┐               │                                           │
│  │ SwiftUI + Connect JS bridge    │---- F1 app_id/env/enrollment --> [TB] --------------------┘
│  │ (connect callbacks, deep links)│
│  └──────────────┬─────────────────┘
│                 │ F2 token + enrollment_id callback [TB]
│                 v
│  [B3 secrets boundary]                 [AS] shell script execution path
│  ┌────────────────────────────────┐     ┌──────────────────────────────────────────────────┐
│  │ 1psa CLI + ~/.teller files     │<--->│ numbered scripts + python entrypoints            │
│  │ cert/key/auth_token/enrollment │ F3  │ 18_fetch_teller_api_data.py / 18_run_* / 20_*    │
│  └──────────────┬─────────────────┘     └───────────────────────────────┬──────────────────┘
│                 │ F5 token/cert/key read [TB]                           │ F6 SQL writes/reads [TB]
│                 v                                                       v
│                                           [B4 DB boundary]
│                                ┌──────────────────────────────────────┐
│                                │ PostgreSQL (teller schema)           │
│                                │ roles, grants, triggers, audit paths │
│                                └──────────────────────────────────────┘
│
│  [AS] FastAPI endpoints:
│  - local classification API routes (health/read/write/matchy proxy)
│  - key risk classes: authz bypass, injection, unsafe deserialization, over-broad CORS
│
│  [AS] dependency/toolchain supply chain:
│  - pip + brew + security scanner binaries + cloned helper repos
│  - key risk classes: poisoned package/update, malicious transitive dependency, tampered tool binary
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Primary data flows and ownership:
- F1 Connect bootstrap request (owner: macOS UI): send app/environment context into WKWebView connect session.
- F2 Connect callback secrets (owner: macOS UI + setup service): receive token/enrollment_id and persist into `~/.teller` with restrictive file permissions.
- F3 Secret retrieval for runtime (owner: shell/python runtime): resolve write token from `1psa`; resolve Teller API cert/key/token from `~/.teller`.
- F4 Teller API exchange (owner: ingest runtime): outbound mTLS + token-auth requests and inbound institution/account/transaction payloads.
- F5 Local API mutation auth (owner: FastAPI): require `X-Teller-Write-Token` backed by `1psa` item resolution before write operations.
- F6 Persistence path (owner: DB + API/ingest): validated SQLAlchemy writes into `teller` schema under least-privilege role assumptions.

Threat ownership map (who mitigates what):
- Local host compromise (B1): repository owners enforce script hygiene, path validation, and explicit command dependencies.
- Secret exfiltration (B3): setup/runtime owners enforce `~/.teller` permission model, narrow secret file set, and `1psa`-only token source for mutations.
- External API contract abuse (B2): ingest/connect owners enforce mTLS + token usage and controlled retry/reconnect behavior.
- DB integrity escalation (B4): schema/API owners enforce authz on write endpoints, parameterized ORM usage, and verification/audit tests.
- Supply-chain compromise (AS): platform owners enforce freshness/security lanes (`04/06/20`) and fail-gates on high/critical findings.


8) OPERATIONS / RECOVERY FLOW (BACKUP, RESTORE, DESTROY)
---------------------------------------------------------
Why: Scripts `97/98/99` are critical but easy to misuse without a flow diagram.

```text
Normal operations running
      |
      v
Run 97_backup_database.sh
      |
      +--> Resolves postgres credential via:
      |      POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD (defaults localhost_postgres_postgres/password)
      |      -> writes <db>_<timestamp>.dump + matching _globals.sql
      |
      v
Verify backup artifacts exist and are readable
      |
      +--> if missing/corrupt: STOP and re-run 97
      |
      v
[Optional destructive step?]
      |
      +--> no  -> skip to restore preflight
      |
      +--> yes -> Run 98_destroy_database.sh
                 |
                 +--> profile selection (via db_profile_export.sh):
                 |      TELLER_DB_PROFILE env override
                 |      -> else db_profiles default_profile
                 |      -> target local vs managed
                 |
                 +--> if managed target:
                 |      destroy schema + roles (not DROP DATABASE)
                 |      credential resolution: env override -> PG_ONEPSA_ITEM via 1psa
                 |
                 +--> if local target:
                 |      destroy database + teller user/roles
                 |      password resolution: POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD via 1psa
                 |
                 +--> requires explicit "destroy" confirmation
      |
      v
Run 99_restore_database.sh
      |
      +--> restore credential resolution order:
      |      1) POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD (admin restore actions)
      |      2) TELLER_PSA_ITEM/TELLER_PSA_FIELD (post-restore teller login reset/verification)
      |
      +--> schema exists? (full restore mode)
      |      - yes and no --table: refuse restore (safety stop)
      |      - no: continue full restore
      |      - scoped --table restore: allowed into existing schema
      |
      +--> full restore order:
      |      restore matching globals first -> restore dump with --create
      |      -> ALTER USER teller to current 1psa secret
      |      -> verify teller can authenticate
      |
      v
Post-restore verification
      |
      +--> ./08_deploy_database_verification_test.sh
      +--> ./21_classification_persistence_verification_test.sh
```

Operational notes:
- Treat `97` as mandatory before any destructive `98` action.
- `99` requires a matching `_globals.sql` companion file for full restore mode.
- Use `--table schema.table` in `99` for targeted repair when full schema replacement is not desired.
```

