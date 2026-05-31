# teller

Local-first Teller data platform: profile-driven PostgreSQL/SQLite schema + ingest scripts + classification API + native macOS review app.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01_install_prerequisites.sh`
  - Ensures Homebrew, required tooling (`shellcheck`, `swiftlint`, `bats`, `gitleaks`, `clamscan`, OWASP ZAP), `1psa`, and sibling repos (`pg_install`, `pgtap`) are present.
  - Ensures Xcode first-launch and license acceptance are completed (using `1psa` for sudo credential input when needed).
- `02_create_venv.sh`
- `03_prepare_supply_chain_integrity.sh`
- `04_load_requirements.sh`
- `05_install_classifier_api_tls.sh`
- `06_deploy_database.sh`
- `07_fetch_teller_api_data.py`
- `08_backfill_bank_statements.py`
- `09_run_classification_api.py`
- `10_run_classification_macos_ui.sh`
- `11_run_all_tests_parallel.sh`
- `12_report_quality_trends.sh`
- `13_validate_quality_target.sh`
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
./03_prepare_supply_chain_integrity.sh
./04_load_requirements.sh
./05_install_classifier_api_tls.sh
mkdir -p config/local
cp config/db-profiles-EXAMPLE.json config/db-profiles.json
# Edit config/db-profiles.json default_profile / 1psa_or_env_item for your environment.
./06_deploy_database.sh
./07_fetch_teller_api_data.py
./08_backfill_bank_statements.py
./09_run_classification_api.py
./10_run_classification_macos_ui.sh
./11_run_all_tests_parallel.sh
```

Before `./06_deploy_database.sh`, ensure dependencies match your selected profile target: PostgreSQL installed/running for `local`/`supabase*` targets, or `sqlcipher` installed for `sqlite` target.
For sqlite profile runs, the default database path is `.database/teller.sqlite3` (override with `TELLER_DB_SQLITE_PATH`).
For sqlite profile runs, set the encryption key via `TELLER_DB_SQLCIPHER_KEY` or the profile `sqlcipher_key` field.
For sqlite profile runs, money values are persisted as integer minor units (cents) in `transaction.amount`, `transaction.running_balance`, `account_balances.ledger`, and `account_balances.available`.
Current architecture assumes Teller API account currency is USD for sqlite money persistence.

## Repository Layout

- `src/teller/` - Python package (ORM models, DB profile/engine, ingest persistence, FastAPI classification API, Mailcart proxy client).
- `src/macos-ui/` - SwiftUI desktop app (`TransactionClassifier`) for Match Review, category management, and Connect enrollment flows.
- `src/sql/postgres/` - canonical PostgreSQL schema objects, triggers, and views for the `teller` schema.
- `tests/` - `py/` (`unittest`), `sh/` (`bats`), `sql/` (`pgTAP`), plus `swift/` and `swift-ui/` symlinks into `src/macos-ui/Tests` and `src/macos-ui/UITests` for snapshot + XCUITest lanes.
- `requirements/` - requirements traceability docs mapped to source `#R...` tags.

## Testing and Verification

Run checks from the project root after activating the virtual environment:

```bash
source ./teller-venv/bin/activate
```

### Quick Profiles

PR-fast profile (recommended default):

```bash
source ./teller-venv/bin/activate
./tests/t04_run_requirements_traceability_tests.sh
./tests/t07_run_shell_unit_tests.sh
./tests/t08_run_python_unit_tests.sh
./tests/t06_run_sql_unit_tests.sh
./tests/t10_run_swift_unit_tests.sh
RUN_SCHEMATHESIS=true RUN_ZAP=false SCHEMATHESIS_FAIL_ON_FINDINGS=true ./tests/t12_run_dynamic_security_tests.sh
RUN_XCUITESTS=false ./tests/t14_run_macos_ui_regression_tests.sh
```

Full-confidence profile (parallel aggregate gate):

```bash
source ./teller-venv/bin/activate
PARALLEL_CLASSIFIER_API_PORT=8787 \
PARALLEL_DAST_BASE_PORT=8788 \
PARALLEL_DAST_REUSE_EXISTING_API=false \
./11_run_all_tests_parallel.sh
```

Quality trend / target checks:

```bash
./12_report_quality_trends.sh
./13_validate_quality_target.sh
```

Supply-chain lock refresh:

```bash
source ./teller-venv/bin/activate
./03_prepare_supply_chain_integrity.sh
```

This step compiles `requirements.in` and `requirements/security/requirements-security.in` into hash-pinned lockfiles and prepares SBOM/signing scaffold artifacts before install/test flows.

### Individual Test Lanes

All primary lanes live under `tests/t*.sh`:

- `./tests/t00_run_code_quality_tests.sh` - code-quality analyzers (Python: Vulture, Radon, Xenon; Swift: Periphery, Lizard)
- `./tests/t01_run_av_test.sh` - antivirus scan (ClamAV)
- `./tests/t02_run_dependency_freshness_tests.sh` - dependency + PostgreSQL + Teller API freshness
- `./tests/t03_run_static_security_tests.sh` - static security scanning (SAST)
- `./tests/t04_run_requirements_traceability_tests.sh` - requirements to `#R...` tag traceability
- `./tests/t05_deploy_database_verification_test.sh` - deployed database invariant checks
- `./tests/t06_run_sql_unit_tests.sh` - SQL unit tests (pgTAP for PostgreSQL targets, sqlcipher SQL checks for SQLite target)
- `./tests/t07_run_shell_unit_tests.sh` - shell unit tests (`bats`)
- `./tests/t08_run_python_unit_tests.sh` - Python unit tests
- `./tests/t09_run_mutation_tests.sh` - mutation testing (`mutmut`)
- `./tests/t10_run_swift_unit_tests.sh` - Swift unit tests
- `./tests/t11_run_fuzz_tests.sh` - property/stateful fuzz tests (Hypothesis)
- `./tests/t12_run_dynamic_security_tests.sh` - dynamic security scanning (DAST, optional ZAP)
- `./tests/t13_run_teller_api_smoke_tests.sh` - Teller API smoke checks
- `./tests/t14_run_macos_ui_regression_tests.sh` - macOS UI snapshot + XCUITest regression
- `./tests/t15_verify_macos_crash_test.sh` - macOS crash reporter verification
- `./tests/t16_classification_persistence_verification_test.sh` - classification API to Postgres persistence E2E
- `./tests/t17_run_teller_live_canary_test.sh` - strict live Teller upstream canary (requires mTLS + token)
- `./tests/t18_verify_filevault_encryption_test.sh` - macOS FileVault encryption verification

Equivalent direct Python invocation:

```bash
python3 -m unittest discover tests/py
```

### Useful Notes

- `11_run_all_tests_parallel.sh` orchestrates `tests/t*.sh` lanes and writes lane logs/artifacts.
- Hypothesis and related caches are stored under `artifacts/cache/` (not a root-level `.hypothesis/`).
- Security and freshness outputs are written under `artifacts/security/`.
- Fuzz outputs are written under `artifacts/fuzz/`.

## API Reference Docs

Local Teller API reference notes now live under `docs/teller-api-reference/`.

## Secret Sources

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
- `~/.env` for local runtime settings loaded by `07_fetch_teller_api_data.py`

## What Each Core Script Does

- `01_install_prerequisites.sh`
  - Verifies/installs local prerequisites (Homebrew, dev/security tooling, `1psa`, `pg_install`, `pgtap`, and first-run Xcode readiness).
- `02_create_venv.sh`
  - Creates `<repo>-venv` using `python3.12` (fallback `python3`) and wires test cache env defaults into the venv activation script.
- `03_prepare_supply_chain_integrity.sh`
  - Compiles hash-pinned lockfiles from `requirements.in` manifests and emits supply-chain artifacts (`sbom.cdx.json`, signing scaffold, attestation) under security reports.
- `04_load_requirements.sh`
  - Installs Python dependencies from `requirements.txt` (or `requirements-cpu.txt` / `requirements-gpu.txt` when used) into the active project venv.
- `05_install_classifier_api_tls.sh`
  - Installs/refreshes locally trusted TLS cert/key files used by `09_run_classification_api.py` (via `mkcert`, under `~/.teller` by default).
- `06_deploy_database.sh`
  - Resolves DB profile and deploys schema/roles/DDL for local or managed targets from `src/sql/postgres/` in dependency order.
  - For sqlite target/profile, applies `src/sql/sqlite/create_database.sql` to `.database/teller.sqlite3` by default.
- `07_fetch_teller_api_data.py`
  - Pulls Teller API data, normalizes and deduplicates transaction history, and persists or upserts accounts, transactions, and related objects into Postgres.
- `08_backfill_bank_statements.py`
  - OCR-parses bank statement PDFs, derives typed/signed transactions, and backfills missing statement-linked transaction rows.
- `09_run_classification_api.py`
  - Starts the local classifier FastAPI service (HTTPS only), requires `1psa` write token, and requires local TLS cert/key files.
- `10_run_classification_macos_ui.sh`
  - Builds and launches the native macOS app (`TransactionClassifier`) with in-process Connect flows; supports optional transaction-list profiling.
- `11_run_all_tests_parallel.sh`
  - Orchestrates all numbered `tests/t*.sh` checks in parallel, captures per-lane logs/artifacts, and updates quality telemetry summaries.
- `12_report_quality_trends.sh`
  - Reads telemetry and prints a local quality trend summary (latest score, rolling windows, and SLO status).
- `13_validate_quality_target.sh`
  - Enforces quality target gates from historical telemetry (including consecutive-week attainment checks).
- `14_prune_quality_telemetry.sh`
  - Prunes old lane-summary telemetry files, retaining the newest configured count.

Core lane scripts under `tests/`:

- `tests/t00_run_code_quality_tests.sh`
  - Runs static code-quality analyzers and writes reports to `artifacts/quality/reports`. Python lane: Vulture (dead code), Radon (complexity metrics), Xenon (complexity gate). Swift lane: Periphery (dead code; Vulture analog) and Lizard (complexity report + threshold gate; Radon+Xenon analog).
- `tests/t01_run_av_test.sh`
  - Runs ClamAV lane (24h signature freshness check, enforced stale-signature refresh, scan, and missing-DB refresh retry).
- `tests/t02_run_dependency_freshness_tests.sh`
  - Runs dependency freshness, Teller API version freshness, and PostgreSQL freshness/CVE checks.
- `tests/t03_run_static_security_tests.sh`
  - Runs SAST tooling and writes security reports.
- `tests/t04_run_requirements_traceability_tests.sh`
  - Validates requirements-to-source traceability via `#R...` tags.
- `tests/t05_deploy_database_verification_test.sh`
  - Verifies deployed database invariants (schema objects, constraints/triggers, role expectations by target).
- `tests/t06_run_sql_unit_tests.sh`
  - Runs only SQL unit-test lane.
- `tests/t07_run_shell_unit_tests.sh`
  - Runs only shell unit-test lane.
- `tests/t08_run_python_unit_tests.sh`
  - Runs only Python unit-test lane.
- `tests/t09_run_mutation_tests.sh`
  - Runs mutation testing (`mutmut`) with score/coverage gating and mutation telemetry output.
- `tests/t10_run_swift_unit_tests.sh`
  - Runs only Swift unit-test lane.
- `tests/t11_run_fuzz_tests.sh`
  - Runs property/stateful fuzz tests (Hypothesis) with budget/time gating.
- `tests/t12_run_dynamic_security_tests.sh`
  - Runs DAST lane (including Schemathesis and optional ZAP flows).
- `tests/t13_run_teller_api_smoke_tests.sh`
  - Runs Teller API smoke checks and writes JSON/text smoke artifacts.
- `tests/t14_run_macos_ui_regression_tests.sh`
  - Runs macOS UI snapshot and XCUITest regression flows.
- `tests/t15_verify_macos_crash_test.sh`
  - Verifies macOS UI crash-reporter behavior and recovery metadata handling.
- `tests/t16_classification_persistence_verification_test.sh`
  - End-to-end API-to-DB persistence check for classification writes.

Operational recovery scripts:

- `97_backup_database.sh`
  - Creates timestamped custom-format DB backup plus matching globals dump for PostgreSQL targets, then encrypts artifacts to `.gpg`.
  - For sqlite target/profile, copies the sqlite DB file (default `.database/teller.sqlite3`) to `backups/*.dump.gpg`.
- `98_destroy_database.sh`
  - Performs explicit-confirmation teardown for local DB or managed schema/roles based on active profile.
  - For sqlite target/profile, performs explicit-confirmation file delete of the sqlite DB path.
- `99_restore_database.sh`
  - Restores latest (or selected) encrypted backup with full-restore safety checks, globals-first flow, and optional table-scoped restore mode.
  - For sqlite target/profile, restores by decrypting/copying the backup dump file to the sqlite DB path.

### Operations Recovery Flow (`97` -> `98` -> `99`)

Use this flow to avoid destructive misuse of backup/destroy/restore scripts:

```text
normal operations
      |
      v
97_backup_database.sh
      |
      +--> resolve active profile (TELLER_DB_PROFILE -> db-profiles.json default)
      +--> local target  : pg_dump prod via postgres admin + pg_dumpall globals
      +--> managed target: switch to supabase_direct, schema-scoped pg_dump (no globals)
      +--> verify <profile>_<db>_<timestamp>.dump.gpg (+ _globals.sql.gpg for local) exist
      |
      v
optional destructive teardown?
      |
      +--> no  -> continue to restore preflight
      |
      +--> yes -> 98_destroy_database.sh
      |           |
      |           +--> profile selection: TELLER_DB_PROFILE override -> db_profiles default_profile
      |           +--> local target: drop DB + roles
      |           +--> managed target: drop schema + roles (no DROP DATABASE)
      |           +--> confirmation gate: must type "destroy"
      |
      v
99_restore_database.sh
      |
      +--> resolve active profile (TELLER_DB_PROFILE -> db-profiles.json default)
      +--> local target  : full restore allowed; preflight refuses if teller schema exists
      |                    restore order: globals first -> dump -> teller password reset/verification
      +--> managed target: full restore refused (cannot CREATE DATABASE / restore globals)
      |                    require --table schema.table_name for scoped restore
      |
      v
post-restore verification
      |
      +--> ./tests/t05_deploy_database_verification_test.sh
      +--> ./tests/t16_classification_persistence_verification_test.sh
```

Credential source resolution order used by recovery scripts:

- `97_backup_database.sh`:
  - profile resolution: `TELLER_DB_PROFILE` env override, otherwise profile file `default_profile`
  - managed target: re-resolves via `supabase_direct` profile; password from env override or profile `PG_ONEPSA_ITEM` via `1psa`
  - local target: `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD` via `1psa` (defaults `localhost_postgres_postgres` / `password`)
  - backup encryption: `POSTGRES_BACKUP_ENCRYPTION` (`type`, `gpg_recipient`, `gpg_public_key`) via `1psa -f`; falls back to `POSTGRES_BACKUP_ENCRYPTION_*` env vars when field lookup is empty/unavailable
- `98_destroy_database.sh`:
  - profile resolution: `TELLER_DB_PROFILE` env override, otherwise profile file `default_profile`
  - managed target credential source: env override first, then profile `PG_ONEPSA_ITEM` via `1psa`
  - local target credential source: `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD` via `1psa`
- `99_restore_database.sh`:
  - profile resolution: `TELLER_DB_PROFILE` env override, otherwise profile file `default_profile`
  - managed target: full restore refused; `--table` scoped restore uses profile `PG_ONEPSA_ITEM` via `1psa`
  - local target admin actions: `POSTGRES_PSA_ITEM`/`POSTGRES_PSA_FIELD`
  - teller post-restore credential check/reset (local only): `TELLER_PSA_ITEM`/`TELLER_PSA_FIELD`
  - backup decryption: `POSTGRES_BACKUP_ENCRYPTION` (`type`, `gpg_private_key`, `gpg_private_key_passphrase`) via `1psa -f`; falls back to `POSTGRES_BACKUP_ENCRYPTION_*` env vars when field lookup is empty/unavailable (`pragma: allowlist secret`)

## Ingest + Normalization + Persistence

### Sequence (`07_fetch_teller_api_data.py`)

Why this flow matters: it makes reruns safe and clarifies where idempotency is enforced before data lands in Postgres.

```text
[scheduler/manual]
      |
      v
07_fetch_teller_api_data.py
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
./10_run_classification_macos_ui.sh
```

Connect behavior:

- Open the **Connect** tab to add, reconnect, or delete local enrollment contexts.
- Successful Connect writes `auth_token*.json` and `enrollment_id*.txt` with restrictive permissions.
- Local setup checks for Teller connectivity are available via in-app setup/smoke actions backed by `TellerSetupService`.
- `07_fetch_teller_api_data.py` now launches the macOS app for repair workflows when disconnected enrollments are detected.

Quality/security aggregate checks are available through:

```bash
./11_run_all_tests_parallel.sh
```

## 1psa Items Used by Database Scripts

`06_deploy_database.sh`, `97_backup_database.sh`, `98_destroy_database.sh`, and `99_restore_database.sh` read credentials from `1psa`.

Default items/fields:

- Postgres admin password:
  - item: `localhost_postgres_postgres`
  - field: `password`
- Teller user password:
  - item: `localhost_postgres_teller`
  - field: `password`
- Backup encryption/decryption contract:
  - item: `POSTGRES_BACKUP_ENCRYPTION`
  - required fields:
    - `type` (`gpg`)
    - `gpg_recipient`
    - `gpg_public_key`
    - `gpg_private_key`
    - `gpg_private_key_passphrase`

Optional overrides:

- `POSTGRES_PSA_ITEM`
- `POSTGRES_PSA_FIELD`
- `TELLER_PSA_ITEM`
- `TELLER_PSA_FIELD`
- `BACKUP_ENCRYPTION_ITEM` (defaults to `POSTGRES_BACKUP_ENCRYPTION`)

Encrypted-backup `.env` fallback fields (used when `1psa -f` lookup is empty/unavailable):

- `POSTGRES_BACKUP_ENCRYPTION_TYPE`
- `POSTGRES_BACKUP_ENCRYPTION_GPG_RECIPIENT`
- `POSTGRES_BACKUP_ENCRYPTION_GPG_PUBLIC_KEY`
- `POSTGRES_BACKUP_ENCRYPTION_GPG_PRIVATE_KEY`
- `POSTGRES_BACKUP_ENCRYPTION_GPG_PRIVATE_KEY_PASSPHRASE`

Example:

```bash
POSTGRES_PSA_ITEM=my_postgres_admin TELLER_PSA_ITEM=my_teller_user ./06_deploy_database.sh
```

Generate a dedicated backup GPG keypair (interactive passphrase prompt):

```bash
./src/scripts/security/generate_backup_gpg_keys.sh
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
  - Fix: update the corresponding `1psa` item, then rerun `./06_deploy_database.sh`.
- `could not connect to server on socket ...`
  - Cause: PostgreSQL is not running or listening on expected host/socket.
  - Fix: start PostgreSQL (for example via Homebrew service) and retry.

## Architecture

Detailed system and data-flow documentation now lives in `Architecture.md`.