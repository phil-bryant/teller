# Prepare Supply-Chain Integrity Requirements

## Scope

Applies to `03_prepare_supply_chain_integrity.sh`.

R001  Statement: Run a dedicated pre-install integrity step before dependency installation.
Design: Provide numbered script `03_prepare_supply_chain_integrity.sh` as the canonical supply-chain prep entrypoint before `04_load_requirements.sh`.
Tests:
- R001-T01: Verify script exists and is executable at repo root.

R005  Statement: Require the project virtual environment to exist and be active.
Design: Validate `<repo>-venv` existence, `VIRTUAL_ENV` presence, and active path match before any pip-tools compilation.
Tests:
- R005-T01: Verify script fails when venv directory is missing.
- R005-T02: Verify script fails when no active virtual environment is set.

R010  Statement: Compile runtime and security lockfiles with hashes from `.in` sources.
Design: Require `pip-compile` on `PATH` (installed by prerequisites), remove legacy venv-installed `pip-tools` when present, and run `pip-compile --generate-hashes` for both `requirements.in` and `requirements/security/requirements-security.in`.
Tests:
- R010-T01: Verify pip-tools compile command is invoked with `--generate-hashes` for runtime lockfile.
- R010-T02: Verify pip-tools compile command is invoked with `--generate-hashes` for security lockfile.

R015  Statement: Generate SBOM and signing scaffold artifacts during pre-install step.
Design: Invoke `src/scripts/security/generate_supply_chain_artifacts.py` with runtime/security lockfile inputs and configured signing mode.
Tests:
- R015-T01: Verify artifact generator is invoked and writes outputs to security report path.

## Changelog

- 2026-05-30: Initial requirements for pre-03 supply-chain integrity preparation script.
