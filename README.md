# teller

Local-first Teller data platform: profile-driven PostgreSQL/SQLite schema, the portable C++ core
(`tellercore`, under `src/core/`), and the shared `teller_db` / `teller_db_profile` / `teller_persist` /
`teller_mailcart_client` Python modules. Owns the database schema and the bank-ingest persistence library
used by sibling repos.

> Note: The **classification API** and the **macOS review UI** were extracted into the sibling
> [`classy`](../classy) repo. Run them from there (`../classy/src/core/scripts/launch_dast_targets.py`
> for DAST API surfacing, `../classy/03_run_classification_macos_ui.sh` for the native app). `classy` imports this package for DB/session/profile/mailcart-client
> and reads/writes `classy.*` and `matchy.*` product-state schemas while keeping relational joins to `teller.transaction`. The classifier API/UI scripts, their TLS installer, and the
> Swift/macOS lanes (classy `t08`/`t11`/`t12`/`t13`) now live in `classy`.
>
> The bank-ingest scripts (`07_fetch_teller_api_data.py`, `08_backfill_bank_statements.py`) are **active**
> and live at the repo root (an earlier README revision mislabeled them as deprecated). The API ingest also
> has a C++ port (`teller_fetch`, built from `src/core/`) verified for output parity against the Python
> script; the OCR statement backfill (`08`) remains Python-only.

## C++ Core (`src/core/`)

`tellercore` is the C++20 port of the Python library's db/profile/persist/mailcart layers, following the
migration pattern established in `classy`. Python is **not** retired: `matchy` still imports
`teller.teller_db` / `teller_db_profile`, so both implementations coexist (with the t17 oracle lane proving
behavioral parity) until matchy migrates.

- `src/core/include/tellercore/`, `src/core/src/` - static library: profile resolution (PostgreSQL +
  SQLite/SQLCipher targets, 1psa via `dlopen` + `~/.env` fallback), dual DB backends (SQLCipher and libpq),
  the `persist_all` ingest upsert layer, and the Mailcart HTTPS client.
- `src/core/include/tellercore/ffi.h` - C ABI (`teller_core_open` / `teller_core_invoke` /
  `teller_core_free` / `teller_core_close`) with the same JSON envelope contract as `classycore`.
- `src/core/tools/` - `teller_fetch` (mTLS API ingest CLI) and `teller_oracle_runner` (parity harness CLI).
- `src/core/oracle/` - `scenarios.json` + `compare_oracle.py`: every persist scenario runs through both the
  Python reference and the C++ core on identical fixtures; full-database snapshots must match.

```bash
make core      # cmake build (RelWithDebInfo)
make test      # t15: Catch2 unit suite
make sanitize  # t16: ASan+UBSan rebuild + rerun
make parity    # t17: Python/C++ oracle parity (sqlite always; postgres when admin creds available)
make pg-test   # t18: [postgres] integration cases against a provisioned scratch database
```

Embedding the static library requires linking: `-ltellercore -lsqlcipher -lpq -lssl -lcrypto -lz` plus
`-framework CoreFoundation -framework Security` on macOS.

## Pre-release CI/CD Policy

Until the `v1.0` customer release, GitHub Actions CI is **implemented but intentionally disabled for automatic
runs**. A workflow exists at `.github/workflows/ci.yml`, but it is **manual-dispatch-only**
(`on: workflow_dispatch`) — it does **not** trigger on `push`, `pull_request`, or `schedule`. Pre-release, the
enforcement mechanism is the local numbered test lanes (`tests/tNN_*.sh` + `./06_run_all_tests_parallel.sh`),
not GitHub-hosted CI: this project is solo and red X's on every push are noise rather than signal. The workflow
runs only the Linux-portable subset (code quality `t00` + Python unit `t08` + requirements traceability `t04`);
the macOS / Swift / 1psa / SQLCipher / PostgreSQL / pgTAP / ZAP / Teller-live / FileVault lanes cannot run on a
Linux runner and stay local. It is kept correct and manually runnable so it can simply be wired to
`push`/`pull_request` as the project approaches `v1.0`.

This policy is consistent across the eggnest workspace (`classy`, `matchy`, `mailcart`, `runner`, and the
`eggnest` umbrella each carry the same manual-dispatch-only workflow and policy note).
Git submodules are intentionally avoided until `v1.0` ships to customers.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01_install_prerequisites.sh`
  - Ensures Homebrew, required tooling (`shellcheck`, `swiftlint`, `bats`, `gitleaks`, `clamscan`, OWASP ZAP), `1psa`, and sibling repos (`pg_install`, `pgtap`) are present.
  - Ensures Xcode first-launch and license acceptance are completed (using `1psa` for sudo credential input when needed).
- `02_create_venv.sh`
- `03_prepare_supply_chain_integrity.sh`
- `04_load_requirements.sh`
- `05_deploy_database.sh`
- `06_run_all_tests_parallel.sh`
- `...` (any future numbered scripts)
- `96_clean_generated_files.sh` (moves generated artifacts to `~/.Trash`)
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
mkdir -p config/local
cp config/db-profiles-EXAMPLE.json config/db-profiles.json
# Edit config/db-profiles.json default_profile / 1psa_or_env_item for your environment.
./05_deploy_database.sh
./06_run_all_tests_parallel.sh
```

The classification API surfacing and macOS UI live in `classy`
(`../classy/src/core/scripts/launch_dast_targets.py`, `../classy/03_run_classification_macos_ui.sh`); run them from that repo.

Before `./05_deploy_database.sh`, ensure dependencies match your selected profile target: PostgreSQL installed/running for `local`/`supabase*` targets, or `sqlcipher` installed for `sqlite` target.
For sqlite profile runs, the default database path is `.database/teller.sqlite3` (override with `TELLER_DB_SQLITE_PATH`).
For sqlite profile runs, set the encryption key via `TELLER_DB_SQLCIPHER_KEY` or the profile `sqlcipher_key` field.
For sqlite profile runs, money values are persisted as integer minor units (cents) in `transaction.amount`, `transaction.running_balance`, `account_balances.ledger`, and `account_balances.available`.
Current architecture assumes Teller API account currency is USD for sqlite money persistence.

## Repository Layout

- `src/teller/` - Python package (ORM models, DB profile/engine, ingest persistence, Mailcart proxy client). Imported by `classy` and `matchy`.
- `src/core/` - portable C++ core (`tellercore`): profile/db/persist/mailcart port, FFI, ingest CLI, oracle parity harness.
- `src/sql/postgres/` and `src/sql/sqlite/` - canonical schema objects, triggers, and views for the `teller` schema (PostgreSQL) plus the SQLite/SQLCipher bootstrap.
- `tests/` - `py/` (`unittest`), `sh/` (`bats`), `sql/` (`pgTAP`), and the self-contained C++ lanes (`t15`-`t18`). Swift/macOS UI lanes live in `classy`.
- `requirements/` - requirements traceability docs mapped to source `#R...` tags.
- `Makefile` - thin facades over the numbered scripts and `tests/t*.sh` lanes (`core`, `test`, `sanitize`, `parity`, `pg-test`, `test-all`, `clean`).

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
RUN_SCHEMATHESIS=true RUN_ZAP=false SCHEMATHESIS_FAIL_ON_FINDINGS=true ./tests/t11_run_dynamic_security_tests.sh
```

Full-confidence profile (parallel aggregate gate):

```bash
source ./teller-venv/bin/activate
PARALLEL_CLASSIFIER_API_PORT=8787 \
PARALLEL_DAST_BASE_PORT=8788 \
PARALLEL_DAST_REUSE_EXISTING_API=false \
./06_run_all_tests_parallel.sh
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
- `./tests/t10_run_fuzz_tests.sh` - property/stateful fuzz tests (Hypothesis)
- `./tests/t11_run_dynamic_security_tests.sh` - dynamic security scanning (DAST, optional ZAP)
- `./tests/t12_run_teller_api_smoke_tests.sh` - Teller API smoke checks
- `./tests/t13_run_teller_live_canary_test.sh` - strict live Teller upstream canary (requires mTLS + token)
- `./tests/t14_verify_filevault_encryption_test.sh` - macOS FileVault encryption verification
- `./tests/t15_run_cpp_core_unit_tests.sh` - C++ core unit tests (Catch2; self-contained, no runner delegation)
- `./tests/t16_run_cpp_core_sanitizer_tests.sh` - C++ core unit suite under ASan+UBSan
- `./tests/t17_run_python_cpp_oracle_parity_test.sh` - Python/C++ oracle parity (persist scenarios diffed on identical fixtures)
- `./tests/t18_run_cpp_postgres_integration_tests.sh` - C++ PostgreSQL integration cases against a provisioned scratch database (skips without admin credentials)

The Swift/macOS UI lanes (classy `t08`, `t11`, `t12`) and classification-persistence lane (classy `t13`) live in `classy`.

Equivalent direct Python invocation:

```bash
python3 -m unittest discover tests/py
```

### Useful Notes

- `06_run_all_tests_parallel.sh` orchestrates `tests/t*.sh` lanes and writes lane logs/artifacts.
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
- Environment variables passed to scripts (for example `POSTGRES_PSA_ITEM`, `TELLER_PSA_ITEM`, `TELLER_DB_PROFILE`, `TELLER_DB_PROFILE_FILE`)
- `~/.env` for local runtime settings consumed by the `src/teller` ingest library

## What Each Core Script Does

- `01_install_prerequisites.sh`
  - Verifies/installs local prerequisites (Homebrew, dev/security tooling, `1psa`, `pg_install`, `pgtap`, and first-run Xcode readiness).
- `02_create_venv.sh`
  - Creates `<repo>-venv` using `python3.12` (fallback `python3`) and wires test cache env defaults into the venv activation script.
- `03_prepare_supply_chain_integrity.sh`
  - Compiles hash-pinned lockfiles from `requirements.in` manifests and emits supply-chain artifacts (`sbom.cdx.json`, signing scaffold, attestation) under security reports.
- `04_load_requirements.sh`
  - Installs Python dependencies from `requirements.txt` (or `requirements-cpu.txt` / `requirements-gpu.txt` when used) into the active project venv.
- `05_deploy_database.sh`
  - Resolves DB profile and deploys schema/roles/DDL for local or managed targets from `src/sql/postgres/` in dependency order.
  - For sqlite target/profile, applies `src/sql/sqlite/create_database.sql` to `.database/teller.sqlite3` by default.
- `06_run_all_tests_parallel.sh`
  - Orchestrates all numbered `tests/t*.sh` checks in parallel and captures per-lane logs/artifacts.

The classifier DAST launcher (`src/core/scripts/launch_dast_targets.py`) and macOS UI launcher
(`03_run_classification_macos_ui.sh`) now live in `classy`. The ingest scripts stay active at the
repo root: `07_fetch_teller_api_data.py` (Teller API ingest; also available as the C++ `teller_fetch` CLI built
from `src/core/`) and `08_backfill_bank_statements.py` (OCR bank-statement backfill).

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
- `tests/t10_run_fuzz_tests.sh`
  - Runs property/stateful fuzz tests (Hypothesis) with budget/time gating.
- `tests/t11_run_dynamic_security_tests.sh`
  - Runs DAST lane (including Schemathesis and optional ZAP flows).
- `tests/t12_run_teller_api_smoke_tests.sh`
  - Runs Teller API smoke checks and writes JSON/text smoke artifacts.
- `tests/t13_run_teller_live_canary_test.sh`
  - Runs the strict live Teller upstream canary (requires mTLS + token).
- `tests/t14_verify_filevault_encryption_test.sh`
  - Verifies macOS FileVault encryption.

Operational recovery scripts:

- `96_clean_generated_files.sh`
  - Clears generated logs/reports and other run artifacts by moving them to `~/.Trash` (no destructive delete).
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
      +--> ../classy/tests/t13_classification_persistence_verification_test.sh
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

### Sequence (`07_fetch_teller_api_data.py` / `teller_fetch`)

The flow below describes how the fetch script (Python `07_fetch_teller_api_data.py` or its C++ port
`src/core/build/teller_fetch`) and the persistence layer normalize and upsert data; it makes reruns safe and
clarifies where idempotency is enforced before data lands in the database.

```text
[scheduler/manual]
      |
      v
07_fetch_teller_api_data.py  (or src/core/build/teller_fetch)
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

After completing Teller Connect in the native app, the returned token is saved under `~/.teller`. The Connect/enrollment UI lives in `classy`:

```bash
../classy/03_run_classification_macos_ui.sh
```

Connect behavior:

- Open the **Connect** tab to add, reconnect, or delete local enrollment contexts.
- Successful Connect writes `auth_token*.json` and `enrollment_id*.txt` with restrictive permissions.
- Local setup checks for Teller connectivity are available via in-app setup/smoke actions backed by `TellerSetupService`.

Quality/security aggregate checks are available through:

```bash
./06_run_all_tests_parallel.sh
```

## 1psa Items Used by Database Scripts

`05_deploy_database.sh`, `97_backup_database.sh`, `98_destroy_database.sh`, and `99_restore_database.sh` read credentials from `1psa`.

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
POSTGRES_PSA_ITEM=my_postgres_admin TELLER_PSA_ITEM=my_teller_user ./05_deploy_database.sh
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
  - Fix: update the corresponding `1psa` item, then rerun `./05_deploy_database.sh`.
- `could not connect to server on socket ...`
  - Cause: PostgreSQL is not running or listening on expected host/socket.
  - Fix: start PostgreSQL (for example via Homebrew service) and retry.

## Architecture

Detailed system and data-flow documentation now lives in `Architecture.md`.