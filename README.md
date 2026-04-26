# teller

Local PostgreSQL schema setup and management scripts for Teller data.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01_install_prerequisites.sh`
  - Ensures Homebrew, required tooling (including `clamscan` from ClamAV), `1psa`, and `pg_install` are present.
  - Ensures Xcode first-launch and license acceptance are completed (using `1psa` for sudo credential input when needed).
- `02_create_venv.sh`
- `03_load_requirements.sh`
- `04_run_dependency_freshness_checks.sh`
- `05_run_unit_tests.sh`
- `06_run_macos_ui_regression_tests.sh` (recommended pre-merge gate; can also be run via `RUN_MACOS_UI_REGRESSION_TESTS=true ./05_run_unit_tests.sh`)
- `07_deploy_database.sh`
- `08_verify_deploy_database.sh`
- `09_verify_updated_at_trigger_coverage.sh`
- `10_configure_teller_io.sh`
- `11_run_teller-connect-ui.sh`
- `12_fetch_teller_api_data.py`
- `13_backfill_bank_statements.py`
- `14_run_classification_api.py`
- `16_run_classification_macos-ui.sh`
- `17_verify_classification_persistence.sh`
- `15_run_security_checks.sh`
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
./04_run_dependency_freshness_checks.sh
./05_run_unit_tests.sh
./07_deploy_database.sh
./08_verify_deploy_database.sh
./06_run_macos_ui_regression_tests.sh
./09_verify_updated_at_trigger_coverage.sh
./15_run_security_checks.sh
./10_configure_teller_io.sh
./11_run_teller-connect-ui.sh
```

## Testing and Verification

Run these checks from the project root after activating the project virtual environment:

```bash
source ./teller-venv/bin/activate
```

Security scanning currently runs via `15_run_security_checks.sh` (SAST and optional DAST).
Dependency freshness automation runs via `04_run_dependency_freshness_checks.sh`.

### 1) Requirements Traceability Verification

Verifies every requirement ID in `requirements/*.md` is mapped to matching `#R...` tags in referenced source files.

```bash
./00_verify_requirements_traceability.sh
```

Optional single-pair mode:

```bash
./00_verify_requirements_traceability.sh requirements/17_verify_classification_persistence-requirements.md 17_verify_classification_persistence.sh
```

### 2) Unit Tests

Runs Python `unittest` coverage for all `tests/test*.py` modules.

```bash
./05_run_unit_tests.sh
```

Equivalent direct unittest invocation:

```bash
python3 -m unittest discover tests
```

Optional macOS UI regression lane:

```bash
RUN_MACOS_UI_REGRESSION_TESTS=true ./05_run_unit_tests.sh
```

### 2b) macOS UI Regression Tests

Runs deterministic snapshot tests and macOS XCUITest smoke flows for `macos-ui`.

This lane can run before Teller configuration (`09`) and Connect enrollment (`10`).

```bash
./06_run_macos_ui_regression_tests.sh
```

Common flags:

- `RUN_SNAPSHOT_TESTS=true|false` (default `true`)
- `SNAPSHOT_RECORD=true|false` (default `false`)
- `RUN_XCUITESTS=true|false` (default `true`)

### 3) Classification Persistence End-to-End Verification

This checks API-to-database persistence by writing one classification via API and reading it back from Postgres.

1. Start the API in one terminal:

```bash
./14_run_classification_api.py
```

2. Run the verifier in another terminal:

```bash
./17_verify_classification_persistence.sh
```

Strict/CI-style mode requiring explicit IDs:

```bash
TXN_ID=txn_xxx CATEGORY_ID=123 ./17_verify_classification_persistence.sh --require-env-ids
```

### 4) Built-In Smoke Verifications in Setup Scripts

These checks run automatically as part of existing setup/token workflows:

- `./10_configure_teller_io.sh`
  - Verifies Teller mTLS connectivity using `GET /institutions`.
  - If `~/.teller/auth_token.json` exists, also checks `GET /accounts`.
- `./11_run_teller-connect-ui.sh`
  - After capture/reconnect/manual token save, runs a best-effort `GET /accounts` verification when `curl`, `jq`, cert/key, and token are available.
  - Prints diagnostics/warnings when verification cannot run or returns non-200.

### 5) Security Scanning (SAST/DAST)

Security scanners are installed automatically into an isolated `.security-venv` when you run the security lane (avoids dependency conflicts with the app venv).

Manual install into `.security-venv` (optional):

```bash
python3 -m venv .security-venv
./.security-venv/bin/pip install --upgrade pip
./.security-venv/bin/pip install -r requirements-security.txt
```

Run the full security lane:

```bash
./15_run_security_checks.sh
```

Useful flags:

- `RUN_SAST=true|false` (default `true`)
- `RUN_DAST=true|false` (default `true`)
- `RUN_SWIFT_SAST=true|false` (default `true`; runs security-focused SwiftLint rules on first-party `./macos-ui` Swift code)
- `RUN_CLAMAV=true|false` (default `true`; runs recursive ClamAV malware scan on repository files)
- `CLAMAV_SCAN_TARGET=/path` (default `.`; scan root for ClamAV repository scan)
- `CLAMAV_HEARTBEAT_SECONDS=15` (default `15`; emits periodic "still scanning" status lines during ClamAV scans)
- `CLAMAV_SIGNATURE_MAX_AGE_HOURS=48` (default `48`; freshness threshold for signature age warning output)
- `RUN_ZAP=true|false` (default `true`, requires local ZAP CLI executable, e.g. `ZAP.sh`)
- `RUN_MACOS_UI_DAST=true|false` (default `true`; runs macOS XCUITest smoke flows through a local ZAP proxy)
- `MACOS_UI_DAST_ZAP_PROXY_HOST` / `MACOS_UI_DAST_ZAP_PROXY_PORT` (defaults `127.0.0.1` / `8090`)
- `MACOS_UI_DAST_REUSE_EXISTING_API=true|false` (default `false`; reuse already-running classification API instead of starting one)
- `SECURITY_FAIL_ON_HIGH_CRITICAL=true|false` (default `true`)
- `RUN_TOKEN_CAPTURE_DAST=true|false|auto` (default `auto`)

Example local macOS UI DAST run:

```bash
RUN_SAST=false RUN_MACOS_UI_DAST=true ./15_run_security_checks.sh
```

ClamAV notes:
- The security script prints the resolved scan target path before scanning.
- It prints signature freshness metadata (latest DB file + age).
- During long scans, it emits periodic heartbeat lines so the run is not silent.
- On first run, if malware signature databases are missing, the script automatically attempts a one-time `freshclam --stdout` update and retries the scan.

For policy and behavior details, see `requirements/15_run_security_checks-requirements.md`.

### 6) Dependency Freshness + Teller API Drift

This lane provides automated dependency update visibility and a Teller compatibility canary.

Run locally:

```bash
./04_run_dependency_freshness_checks.sh
```

Artifacts are written to `./.security-reports/`:

- `dependency-freshness.json` and `dependency-freshness.txt` (outdated package summary with major/minor/patch classification)
- `teller-api-drift.json` and `teller-api-drift.txt` (live canary or fallback compatibility checks)

Useful flags:

- `DEPENDENCY_FAIL_ON_MAJOR=true|false` (default `false`) to fail when major dependency updates are available
- `RUN_TELLER_CANARY=true|false` (default `true`)
- `DEPENDENCY_REPORT_DIR=/path` (default `./.security-reports`)
- `DEPENDENCY_CHECK_PYTHON=/path/to/python` (default `./teller-venv/bin/python` when available)

Triage expectations:

- Patch/minor Dependabot PRs: review CI output, run `./05_run_unit_tests.sh`, then merge when green.
- Major updates: addressed manually after compatibility validation; these are notify-only and not auto-opened by Dependabot config.
- Teller drift failures: fix credentials or investigate endpoint/schema behavior changes before release.

## API Reference Docs

Local Teller API reference notes now live under `docs/teller-api-reference/`.

## Secret Sources

`secrets.txt` is archival context only and is not read by scripts.

Active secret and credential sources are:

- `~/.teller/` files used by Teller workflows:
  - `application_id.txt`
  - `certificate.pem`
  - `private_key.pem`
  - `auth_token.json` and optional `auth_token_<suffix>.json`
  - `enrollment_id.txt` and optional `enrollment_id_<suffix>.txt`
- `1psa` items used by database and setup scripts:
  - `localhost_postgres_postgres` / `localhost_postgres_teller` by default for DB scripts
  - optional Teller item lookups in `10_configure_teller_io.sh`
- Environment variables passed to scripts (for example `TELLER_APPLICATION_ID`, `TELLER_ACCESS_TOKEN`, `POSTGRES_PSA_ITEM`, `TELLER_PSA_ITEM`)
- `~/.env` for local runtime settings loaded by `12_fetch_teller_api_data.py`

## What Each Core Script Does

- `01_install_prerequisites.sh`
  - Ensures Homebrew is installed.
  - Ensures `go`, `git`, `bats`, `swiftlint`, and `clamscan` are available.
  - Installs `1psa` (from `../1psa`) and clones `pg_install` into `../pg_install`.
- `02_create_venv.sh`
  - Creates a Python virtual environment named `<repo>-venv`.
- `03_load_requirements.sh`
  - Installs dependencies from `requirements.txt` (or CPU/GPU variant files).
  - Must be run with the project virtual environment active.
- `05_run_unit_tests.sh`
  - Runs unit tests with `python3 -m unittest discover tests`.
- `07_deploy_database.sh`
  - Creates/configures the `prod` database.
  - Applies SQL schema objects in dependency order from `sql/postgres/`.
- `08_verify_deploy_database.sh`
  - Verifies required database objects and trigger/FK invariants after deploy.
- `06_run_macos_ui_regression_tests.sh`
  - Runs `macos-ui` snapshot regression tests and the macOS XCUITest smoke suite.
  - Supports selective gates with `RUN_SNAPSHOT_TESTS`, `SNAPSHOT_RECORD`, and `RUN_XCUITESTS`.
- `09_verify_updated_at_trigger_coverage.sh`
  - Verifies all `teller` tables with `updated_at` are covered by `teller.update_updated_at`.
- `10_configure_teller_io.sh`
  - Ensures `~/.teller` contains required Teller credentials/config files.
  - Supports importing Teller secrets from environment variables or `1psa`.
  - Runs Teller API smoke tests (`/institutions`, optionally `/accounts`).
- `11_run_teller-connect-ui.sh`
  - Saves a fresh Teller Connect `accessToken` into `~/.teller/auth_token.json`.
  - Default mode is no copy/paste: runs local Connect capture server on `http://localhost:8080`.
  - Persists enrollment id to `~/.teller/enrollment_id.txt` for future repair mode.
  - Also supports token argument, secure prompt (`--manual`), or macOS clipboard mode.
  - Also provides enrollment management (`--list`, `--delete`, `--reconnect`, `--add`).
- `12_fetch_teller_api_data.py`
  - Runs Teller API client operations.
- `13_backfill_bank_statements.py`
  - Backfills statements data.
- `14_run_classification_api.py`
  - Starts local FastAPI service for listing transactions/categories and saving user SNW classifications.
- `16_run_classification_macos-ui.sh`
  - Runs the local macOS UI app wrapper (`swift run TransactionClassifier`) from the repo root.
- `17_verify_classification_persistence.sh`
  - End-to-end check: writes one classification via API then confirms DB persistence.
  - Smart default auto-selects `TXN_ID` and `CATEGORY_ID`; use `--require-env-ids` for strict CI mode.
- `15_run_security_checks.sh`
  - Runs local SAST checks (Semgrep, Bandit, pip-audit, detect-secrets, ClamAV, and SwiftLint for `macos-ui`).
  - Optionally runs DAST inline (starts local API target(s), runs Schemathesis against OpenAPI, and runs OWASP ZAP local CLI quick scan).
  - Supports optional token-capture target scanning when Teller local credentials are present.
- `97_backup_database.sh`
  - Creates a timestamped PostgreSQL custom-format dump in `./backups`.
  - Also captures matching cluster globals (roles/grants) for reliable restores.
- `98_destroy_database.sh`
  - Destroys `prod` database and related roles after explicit confirmation.
- `99_restore_database.sh`
  - Restores latest backup by default (or accepts `--from /path/to/backup.dump`).
  - Exits if `teller` schema already exists in `prod`.
  - Restores matching globals before database objects.

## Reconfiguring Teller.io

`10_configure_teller_io.sh` automates local Teller file provisioning and API checks, but some setup is dashboard/UI-only.

Manual steps (cannot be provisioned through Teller API endpoints):

- Sign in to the Teller Dashboard and confirm your application exists.
- Copy your Application ID from [Application Settings](https://teller.io/settings/application).
- Ensure you have an active Teller client certificate/private key pair.
  - If missing/compromised, revoke and reissue in [Certificates](https://teller.io/settings/certificates).
- If you need a fresh access token, run a Teller Connect enrollment flow and capture `enrollment.accessToken`.
  - This requires user interaction and cannot be fully automated server-side.

Automated by `10_configure_teller_io.sh`:

- Clones Teller's examples repo into `./teller-connect-ui` by default (not a sibling under `../src`).
- Creates and permissions `~/.teller`.
- Writes:
  - `application_id.txt`
  - `certificate.pem`
  - `private_key.pem`
  - `auth_token.json` (optional)
- Verifies Teller API connectivity using mTLS (`/institutions`).
- Verifies token-based account access (`/accounts`) when `auth_token.json` is present.

### `10_configure_teller_io.sh` Input Options

Use one of the following patterns:

- Direct env values:
  - `TELLER_APPLICATION_ID`
  - `TELLER_ACCESS_TOKEN` (optional)
- File paths for certificate/key:
  - `TELLER_CERT_PATH`
  - `TELLER_KEY_PATH`
- `1psa` lookups:
  - `TELLER_APP_PSA_ITEM`, `TELLER_APP_PSA_FIELD`
  - `TELLER_CERT_PSA_ITEM`, `TELLER_CERT_PSA_FIELD`
  - `TELLER_KEY_PSA_ITEM`, `TELLER_KEY_PSA_FIELD`
  - `TELLER_AUTH_PSA_ITEM`, `TELLER_AUTH_PSA_FIELD` (optional)
- Examples repo controls:
  - `TELLER_EXAMPLES_DIR` (default `./teller-connect-ui`)
  - `EXAMPLES_REPO_URL` (default `https://github.com/tellerhq/examples.git`)
  - `CONFIGURE_TELLER_EXAMPLES=true|false` (default `true`)

Example (1psa-backed):

```bash
TELLER_APP_PSA_ITEM=localhost_teller_app \
TELLER_CERT_PSA_ITEM=localhost_teller_cert \
TELLER_KEY_PSA_ITEM=localhost_teller_key \
./10_configure_teller_io.sh
```

### Save Refreshed Access Token

After completing Teller Connect, capture the returned `accessToken`:

```bash
./11_run_teller-connect-ui.sh
```

Default `11` behavior:

- Starts local Teller Connect capture UI at `http://localhost:8080`
- On successful enrollment, automatically writes `~/.teller/auth_token.json`
- Persists enrollment id at `~/.teller/enrollment_id.txt`
- Immediately verifies `/accounts` with the saved token/cert
- Supports repair mode for disconnected enrollments without creating a new enrollment:
  - `ENROLLMENT_ID=enr_xxx ./11_run_teller-connect-ui.sh`
  - Automatic when `AUTO_REPAIR=true` and `~/.teller/enrollment_id.txt` exists

Other options (manual/alternative input):

```bash
./11_run_teller-connect-ui.sh --manual
./11_run_teller-connect-ui.sh token_xxx
./11_run_teller-connect-ui.sh --clipboard
ENROLLMENT_ID=enr_xxx ./11_run_teller-connect-ui.sh
AUTO_REPAIR=false ./11_run_teller-connect-ui.sh
```

### Enrollment Management Status (`11_run_teller-connect-ui.sh`)

Requirements now define `11_run_teller-connect-ui.sh` as the enrollment-management CLI entrypoint.

Required management actions:

- list all known local enrollment contexts
- delete one selected enrollment context
- reconnect (repair) one selected enrollment
- add a new enrollment without overwriting existing contexts

Command examples:

```bash
./11_run_teller-connect-ui.sh --list
./11_run_teller-connect-ui.sh --add
./11_run_teller-connect-ui.sh --reconnect --institution_id first_ak_bank_trust
./11_run_teller-connect-ui.sh --delete --enrollment_id enr_xxx --yes
```

Behavior notes:

- `--add` opens Connect and you pick institution in Teller UI; files are persisted as `auth_token_<suffix>.json`
- `--add` suffix is derived from Teller identity data when available; fallback uses enrollment id, then unique numeric suffix
- `--reconnect` repairs only the selected enrollment context
- `--delete` removes only selected local files and moves them into `~/.Trash`

Then verify token/API access:

```bash
./11_run_teller-connect-ui.sh
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
