# Load Requirements Requirements

## Scope

Applies to `04_load_requirements.sh`.

R001  Statement: Require expected virtual environment directory to exist.
Design: Compute `<cwd-basename>-venv` and fail if missing.
Tests:
- R001-T01: Remove venv directory and verify clear failure with `02_create_venv.sh` guidance.

R005  Statement: Require a currently active virtual environment.
Design: Check `VIRTUAL_ENV`; fail with activation instructions when unset.
Tests:
- R005-T01: Run outside venv and verify non-zero exit with activation hint.

R010  Statement: Require active virtual environment to match expected project venv.
Design: Resolve absolute paths and compare expected/current virtual environment roots.
Tests:
- R010-T01: Activate different venv and verify mismatch warning then non-zero exit.

R015  Statement: Select requirements file by deterministic precedence.
Design: Use `requirements.txt` when present; otherwise use cpu/gpu split flow.
Tests:
- R015-T01: With `requirements.txt` present, verify split-file argument is not required.
- R015-T02: Without `requirements.txt`, verify split-file detection engages.

R020  Statement: Validate cpu/gpu selector when split requirements files are used.
Design: Require exactly one parameter and allow only `cpu` or `gpu`.
Tests:
- R020-T01: Run with missing selector and verify usage failure.
- R020-T02: Run with invalid selector and verify usage failure.

R025  Statement: Install dependencies with a pinned, hash-verified bootstrap pip chain.
Design: Enable `pip` alias to `pip3`, install pinned bootstrap `pip` via temporary hash-pinned requirements (`--require-hashes --only-binary=:all:`), then install selected project requirements with `--require-hashes` when lockfile hashes are present.
Tests:
- R025-T01: Verify bootstrap pip install runs with pinned hash-checking flags before project requirements install.
- R025-T02: Verify selected requirements file is passed to pip install with `--require-hashes` when hash pins are present.

R030  Statement: Preserve manual traceability policy for locked script.
Constraints:
- `04_load_requirements.sh` is locked via `<AI_MODEL_INSTRUCTION>` and cannot be AI-edited.
- Traceability for this file is verified by exception policy, not inline `#R` tags.
Tests:
- R030-T01: Verify locked marker exists in script file.
- R030-T02: Verify batch traceability check reports `04` as policy exception, not failure.

R035  Statement: Keep PostgreSQL driver dependency wheel-based for portable venv installs.
Design: `requirements.txt` must use `psycopg2-binary` so dependency loading does not require host-specific `libpq` paths.
Tests:
- R035-T01: Verify `requirements.txt` contains `psycopg2-binary`.
- R035-T02: Verify `requirements.txt` does not contain plain `psycopg2` package entry.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for locked `04_load_requirements.sh`.
- 2026-05-15: Added R035 to require wheel-based psycopg2 dependency in `requirements.txt`.
- 2026-05-31: Hardened R025 to require pinned bootstrap pip hash verification and hashed project dependency installs when available.
