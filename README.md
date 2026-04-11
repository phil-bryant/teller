# teller

Local PostgreSQL schema setup and management scripts for Teller data.

## Script Execution Order

Run setup scripts in numeric order. The workflow is designed around:

- `01A_install_prerequisites.sh`
- `02_create_venv.sh`
- `03_load_requirements.sh`
- `04_deploy_database.sh`
- `...` (any future numbered scripts)
- `99_destroy_database.sh` (cleanup/teardown)

Do not skip ahead unless you know a later script's dependencies are already satisfied.

## Quick Start

From the project root:

```bash
./01A_install_prerequisites.sh
./02_create_venv.sh
source ./teller-venv/bin/activate
./03_load_requirements.sh
./04_deploy_database.sh
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
- `99_destroy_database.sh`
  - Destroys `prod` database and related roles after explicit confirmation.

## 1psa Items Used by Database Scripts

`04_deploy_database.sh` and `99_destroy_database.sh` read credentials from `1psa`.

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
