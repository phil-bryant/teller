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
- `11_run_sql_unit_tests.sh`
- `12_run_swift_unit_tests.sh`
- `13_run_macos_ui_regression_tests.sh` (recommended pre-merge gate)
- `14_verify_macos_crash_test.sh`
- `15_run_teller_api_smoke_tests.sh`
- `16_fetch_teller_api_data.py`
- `17_backfill_bank_statements.py`
- `18_run_classification_api.py`
- `19_classification_persistence_verification_test.sh`
- `20_run_dynamic_security_tests.sh`
- `21_run_classification_macos-ui.sh`
- `22_run_all_tests_parallel.sh`
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
./11_run_sql_unit_tests.sh
./12_run_swift_unit_tests.sh
./13_run_macos_ui_regression_tests.sh
./14_verify_macos_crash_test.sh
./15_run_teller_api_smoke_tests.sh
./16_fetch_teller_api_data.py
./17_backfill_bank_statements.py
./18_run_classification_api.py
./19_classification_persistence_verification_test.sh
./20_run_dynamic_security_tests.sh
./21_run_classification_macos-ui.sh
./22_run_all_tests_parallel.sh
```

Before `./07_deploy_database.sh`, ensure PostgreSQL is installed and running for your selected profile target (for local runs, start your local server/service first).

## Repository Layout

- `teller/` - Python package (ORM models, DB profile/engine, ingest persistence, FastAPI classification API, Mailcart proxy client).
- `macos-ui/` - SwiftUI desktop app (`TransactionClassifier`) for Match Review, category management, and Connect enrollment flows.
- `sql/postgres/` - canonical schema objects, triggers, and views for the `teller` schema.
- `tests/` - `py/` (`unittest`), `sh/` (`bats`), `sql/` (`pgTAP`) plus `macos-ui` snapshot/XCUITest lanes.
- `requirements/` - requirements traceability docs mapped to source `#R...` tags.

## Testing and Verification

Run these checks from the project root after activating the project virtual environment:

```bash
source ./teller-venv/bin/activate
```

Security scanning runs via `06_run_static_security_tests.sh` (SAST) and `20_run_dynamic_security_tests.sh` (DAST).
Antivirus scanning runs via `05_run_av_test.sh` (ClamAV lane).
Dependency freshness automation runs via `04_run_dependency_freshness_tests.sh`.

### 1) Requirements Traceability Verification

Verifies every requirement ID in `requirements/**/*-requirements.md` is mapped to matching `#R...` tags in referenced source files.

```bash
./00_run_requirements_traceability_tests.sh
```

Optional single-pair mode:

```bash
./00_run_requirements_traceability_tests.sh requirements/19_classification_persistence_verification_test-requirements.md 19_classification_persistence_verification_test.sh
```

### 2) Unit Tests

Runs split unit lanes so each suite can run independently (and in parallel under `22`).

```bash
./09_run_shell_unit_tests.sh
./10_run_python_unit_tests.sh
./11_run_sql_unit_tests.sh
./12_run_swift_unit_tests.sh
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
./13_run_macos_ui_regression_tests.sh
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
./18_run_classification_api.py
```

2. Run the verifier:

```bash
./19_classification_persistence_verification_test.sh
```

Strict/CI-style mode requiring explicit IDs:

```bash
TXN_ID=txn_xxx CATEGORY_ID=123 ./19_classification_persistence_verification_test.sh --require-env-ids
```

Mutation endpoints require a write token from the `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` (checked by `18_run_classification_api.py`).

### 4) Built-In Smoke Verifications in Setup Scripts

These checks run as part of existing app/setup workflows:

- `./21_run_classification_macos-ui.sh`
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
./20_run_dynamic_security_tests.sh
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

For policy and behavior details, see `requirements/06_run_static_security_tests-requirements.md`, `requirements/20_run_dynamic_security_tests-requirements.md`, and `requirements/05_run_av_test-requirements.md`.

### 6) Dependency Freshness + Teller API Smoke

Use separate lanes for dependency/PostgreSQL freshness and Teller API smoke coverage.

Run locally:

```bash
./04_run_dependency_freshness_tests.sh
./15_run_teller_api_smoke_tests.sh
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
- `~/.env` for local runtime settings loaded by `16_fetch_teller_api_data.py`

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
- `13_run_macos_ui_regression_tests.sh`
  - Runs `macos-ui` snapshot regression tests and the macOS XCUITest smoke suite.
  - Supports selective gates with `RUN_SNAPSHOT_TESTS`, `SNAPSHOT_RECORD`, and `RUN_XCUITESTS`.
- `14_verify_macos_crash_test.sh`
  - Validates crash-reporter behavior and expected failure metadata for `macos-ui`.
- `15_run_teller_api_smoke_tests.sh`
  - Runs Teller API smoke checks (`/institutions`, and token-backed `/accounts` / `/identity` when auth resolves).
  - Writes smoke artifacts to `.security-reports/`.
- `16_fetch_teller_api_data.py`
  - Runs Teller API client operations.
- `17_backfill_bank_statements.py`
  - Backfills statements data.
- `18_run_classification_api.py`
  - Starts local FastAPI service for listing transactions/categories and saving user SNW classifications.
  - Requires `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` before serving.
- `19_classification_persistence_verification_test.sh`
  - End-to-end check: writes one classification via API then confirms DB persistence.
  - Smart default auto-selects `TXN_ID` and `CATEGORY_ID`; use `--require-env-ids` for strict CI mode.
- `20_run_dynamic_security_tests.sh`
  - Runs DAST checks (Schemathesis + OWASP ZAP quick scan and related hardening checks) against running/local API targets.
- `21_run_classification_macos-ui.sh`
  - Builds and launches `macos-ui/.build/debug/TransactionClassifier` from the repo root.
  - Connect tab hosts native Teller Connect enrollment/reconnect/add/delete (WebView-backed, no standalone localhost server).
- `22_run_all_tests_parallel.sh`
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
./21_run_classification_macos-ui.sh
```

Connect behavior:

- Open the **Connect** tab to add, reconnect, or delete local enrollment contexts.
- Successful Connect writes `auth_token*.json` and `enrollment_id*.txt` with restrictive permissions.
- Local setup checks for Teller connectivity are available via in-app setup/smoke actions backed by `TellerSetupService`.
- `16_fetch_teller_api_data.py` now launches the macOS app for repair workflows when disconnected enrollments are detected.

Quality/security aggregate checks are available through:

```bash
./22_run_all_tests_parallel.sh
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
┌───────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                            SYSTEM LANDSCAPE                                           │
│                                                                                                       │
│  ┌────────────────────────────────┐      HTTP (search/move)       ┌────────────────────────────────┐  │
│  │             MATCHY             │ ────────────────────────────► │            MAILCART            │  │
│  │                                │ ◄──────────────────────────── │                                │  │
│  │ - FastAPI service              │        message candidates     │ - Outlook/Graph integration    │  │
│  │ - Runs transaction↔email match │                               │ - Search endpoint for emails   │  │
│  │ - Combines scoring + AI ranker │                               │ - Move endpoint to folder      │  │
│  │ - Writes run/candidate/match   │                               │   `matchy`                     │  │
│  │   records to Teller DB         │                               └────────────────────────────────┘  │
│  └───────────────┬────────────────┘                                                                   │
│                  │ SQL read/write                                                                     │
│                  ▼                                                                                    │
│  ┌──────────────────────────────────────────────────────────┐                                         │
│  │                      TELLER DB                           │                                         │
│  │                                                          │                                         │
│  │ - Source transactions: `teller.transaction`              │                                         │
│  │ - Match run table: `teller.transaction_email_match_run`  │                                         │
│  │ - Candidates table: `teller.transaction_email_candidate` │                                         │
│  │ - Match table: `teller.transaction_email_match`          │                                         │
│  └──────────────────────────────────────────────────────────┘                                         │
│                                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘

TRIGGER FLOW
┌─────────────────────────────┐      POST /v1/matchy/runs       ┌────────────────────────────┐
│ Caller (manual/auto/retry)  │───────────────────────────────► │ Matchy API                 │
│ (operator/job in ecosystem) │                                 │ validates ids + starts run │
└───────────────────────────√─┘                                 └────────────────────────────┘
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