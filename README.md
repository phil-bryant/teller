# teller

Local PostgreSQL schema setup and management scripts for Teller data.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01A_install_prerequisites.sh`
- `02_create_venv.sh`
- `03_load_requirements.sh`
- `04_deploy_database.sh`
- `05_configure_teller_io.sh`
- `06_capture_teller_token.sh`
- `07_teller_client.py`
- `08_backfill_statements.py`
- `...` (any future numbered scripts)
- `97_backup_database.sh` (creates timestamped backup + globals)
- `98_destroy_database.sh` (cleanup/teardown)
- `99_restore_database.sh` (restores latest or selected backup)

Do not skip ahead unless you know a later script's dependencies are already satisfied.

## Quick Start

From the project root:

```bash
./01A_install_prerequisites.sh
./02_create_venv.sh
source ./teller-venv/bin/activate
./03_load_requirements.sh
./04_deploy_database.sh
./05_configure_teller_io.sh
./06_capture_teller_token.sh
```

## What Each Core Script Does

- `01A_install_prerequisites.sh`
  - Ensures Homebrew is installed.
  - Ensures `go` and `git` are available.
  - Installs `1psa` (from `../1psa`) and clones `pg_install` into `../pg_install`.
- `02_create_venv.sh`
  - Creates a Python virtual environment named `<repo>-venv`.
- `03_load_requirements.sh`
  - Installs dependencies from `requirements.txt` (or CPU/GPU variant files).
  - Must be run with the project virtual environment active.
- `04_deploy_database.sh`
  - Creates/configures the `prod` database.
  - Applies SQL schema objects in dependency order.
- `05_configure_teller_io.sh`
  - Ensures `~/.teller` contains required Teller credentials/config files.
  - Supports importing Teller secrets from environment variables or `1psa`.
  - Runs Teller API smoke tests (`/institutions`, optionally `/accounts`).
- `06_capture_teller_token.sh`
  - Saves a fresh Teller Connect `accessToken` into `~/.teller/auth_token.json`.
  - Default mode is no copy/paste: runs local Connect capture server on `http://localhost:8080`.
  - Persists enrollment id to `~/.teller/enrollment_id.txt` for future repair mode.
  - Also supports token argument, secure prompt (`--manual`), or macOS clipboard mode.
  - Also provides enrollment management (`--list`, `--delete`, `--reconnect`, `--add`).
- `07_teller_client.py`
  - Runs Teller API client operations.
- `08_backfill_statements.py`
  - Backfills statements data.
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

`05_configure_teller_io.sh` automates local Teller file provisioning and API checks, but some setup is dashboard/UI-only.

Manual steps (cannot be provisioned through Teller API endpoints):

- Sign in to the Teller Dashboard and confirm your application exists.
- Copy your Application ID from [Application Settings](https://teller.io/settings/application).
- Ensure you have an active Teller client certificate/private key pair.
  - If missing/compromised, revoke and reissue in [Certificates](https://teller.io/settings/certificates).
- If you need a fresh access token, run a Teller Connect enrollment flow and capture `enrollment.accessToken`.
  - This requires user interaction and cannot be fully automated server-side.

Automated by `05_configure_teller_io.sh`:

- Clones Teller's examples repo into `./examples` by default (not a sibling under `../src`).
- Creates and permissions `~/.teller`.
- Writes:
  - `application_id.txt`
  - `certificate.pem`
  - `private_key.pem`
  - `auth_token.json` (optional)
- Verifies Teller API connectivity using mTLS (`/institutions`).
- Verifies token-based account access (`/accounts`) when `auth_token.json` is present.

### `05_configure_teller_io.sh` Input Options

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
  - `TELLER_EXAMPLES_DIR` (default `./examples`)
  - `EXAMPLES_REPO_URL` (default `https://github.com/tellerhq/examples.git`)
  - `CONFIGURE_TELLER_EXAMPLES=true|false` (default `true`)

Example (1psa-backed):

```bash
TELLER_APP_PSA_ITEM=localhost_teller_app \
TELLER_CERT_PSA_ITEM=localhost_teller_cert \
TELLER_KEY_PSA_ITEM=localhost_teller_key \
./05_configure_teller_io.sh
```

### Save Refreshed Access Token

After completing Teller Connect, capture the returned `accessToken`:

```bash
./06_capture_teller_token.sh
```

Default `06` behavior:

- Starts local Teller Connect capture UI at `http://localhost:8080`
- On successful enrollment, automatically writes `~/.teller/auth_token.json`
- Persists enrollment id at `~/.teller/enrollment_id.txt`
- Immediately verifies `/accounts` with the saved token/cert
- Supports repair mode for disconnected enrollments without creating a new enrollment:
  - `ENROLLMENT_ID=enr_xxx ./06_capture_teller_token.sh`
  - Automatic when `AUTO_REPAIR=true` and `~/.teller/enrollment_id.txt` exists

Other options (manual/alternative input):

```bash
./06_capture_teller_token.sh --manual
./06_capture_teller_token.sh token_xxx
./06_capture_teller_token.sh --clipboard
ENROLLMENT_ID=enr_xxx ./06_capture_teller_token.sh
AUTO_REPAIR=false ./06_capture_teller_token.sh
```

### Enrollment Management Status (`06_capture_teller_token.sh`)

Requirements now define `06_capture_teller_token.sh` as the enrollment-management CLI entrypoint.

Required management actions:

- list all known local enrollment contexts
- delete one selected enrollment context
- reconnect (repair) one selected enrollment
- add a new enrollment without overwriting existing contexts

Command examples:

```bash
./06_capture_teller_token.sh --list
./06_capture_teller_token.sh --add
./06_capture_teller_token.sh --reconnect --institution_id first_ak_bank_trust
./06_capture_teller_token.sh --delete --enrollment_id enr_xxx --yes
```

Behavior notes:

- `--add` opens Connect and you pick institution in Teller UI; files are persisted as `auth_token_<suffix>.json`
- `--add` suffix is derived from Teller identity data when available; fallback uses enrollment id, then unique numeric suffix
- `--reconnect` repairs only the selected enrollment context
- `--delete` removes only selected local files and moves them into `~/.Trash`

Then verify token/API access:

```bash
./06_capture_teller_token.sh
```

## 1psa Items Used by Database Scripts

`04_deploy_database.sh`, `97_backup_database.sh`, `98_destroy_database.sh`, and `99_restore_database.sh` read credentials from `1psa`.

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
POSTGRES_PSA_ITEM=my_postgres_admin TELLER_PSA_ITEM=my_teller_user ./04_deploy_database.sh
```

## Troubleshooting

- `field 'localhost_postgres_postgres' not found in item ...`
  - Cause: wrong field name was requested.
  - Fix: use `password` field (default), or set `POSTGRES_PSA_FIELD=password`.
- `1psa is required but was not found on PATH`
  - Cause: `1psa` is not installed or not in shell `PATH`.
  - Fix: rerun `./01A_install_prerequisites.sh`, then open a new shell.
- `Failed to read postgres password from 1psa item ...`
  - Cause: item name is wrong, inaccessible, or missing `password` field.
  - Fix: verify with `1psa -l localhost_postgres_postgres` and `1psa -p localhost_postgres_postgres`.
- `Failed to read teller password from 1psa item ...`
  - Cause: teller item is wrong or missing `password`.
  - Fix: verify with `1psa -l localhost_postgres_teller` and `1psa -p localhost_postgres_teller`.
- `psql: ... password authentication failed for user ...`
  - Cause: stored credential does not match the database user password.
  - Fix: update the corresponding `1psa` item, then rerun `./04_deploy_database.sh`.
- `could not connect to server on socket ...`
  - Cause: PostgreSQL is not running or listening on expected host/socket.
  - Fix: start PostgreSQL (for example via Homebrew service) and retry.
