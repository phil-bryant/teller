# Create Venv Requirements

## Scope

Applies to `02_create_venv.sh`.

R001  Statement: Run with bash and fail fast on unrecoverable errors.
Design: Use `set -e` and exit non-zero on hard failures.
Tests:
- R001-T01: Force a failing command and verify script exits non-zero.

R005  Statement: Require sibling prerequisites script to exist.
Design: Verify `01_install_prerequisites.sh` in script directory before continuing.
Tests:
- R005-T01: Rename prerequisites script and verify clear failure message.

R010  Statement: Select Python interpreter with deterministic preference.
Design: Prefer `python3.12`; fallback to `python3`.
Tests:
- R010-T01: With both interpreters available, verify `python3.12` is selected.
- R010-T02: With only `python3`, verify fallback is selected.

R015  Statement: Fail when no supported Python interpreter is present.
Design: Exit non-zero if neither `python3.12` nor `python3` resolves on PATH.
Tests:
- R015-T01: Remove both interpreters from PATH and verify failure.

R020  Statement: Name virtual environment from current directory.
Design: Compute directory as `<cwd-basename>-venv`.
Tests:
- R020-T01: Run in folder `foo` and verify venv target is `foo-venv`.

R025  Statement: Refuse creation when another virtual environment is active.
Design: Check `VIRTUAL_ENV`; print deactivation guidance and exit.
Tests:
- R025-T01: Run with `VIRTUAL_ENV` set and verify script exits non-zero.

R030  Statement: Keep virtual environment creation idempotent.
Design: If target venv directory exists, print activation hint and exit success.
Tests:
- R030-T01: Run script twice and verify second run exits 0 without recreating venv.

R035  Statement: Create virtual environment with selected interpreter.
Design: Execute `<python> -m venv <dir>`.
Tests:
- R035-T01: Verify target directory contains `bin/activate` after creation.

R040  Statement: Print activation guidance after successful or idempotent runs.
Design: Output `activate` command hint in terminal.
Tests:
- R040-T01: Verify output includes activation guidance string.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `02_create_venv.sh`.
