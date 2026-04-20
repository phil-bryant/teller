# Load Requirements Requirements

## Scope

Applies to `03_load_requirements.sh`.

R001  Statement: Require expected virtual environment directory to exist.
Design: Compute `<cwd-basename>-venv` and fail if missing.
Tests:
- Remove venv directory and verify clear failure with `02_create_venv.sh` guidance.

R005  Statement: Require a currently active virtual environment.
Design: Check `VIRTUAL_ENV`; fail with activation instructions when unset.
Tests:
- Run outside venv and verify non-zero exit with activation hint.

R010  Statement: Require active virtual environment to match expected project venv.
Design: Resolve absolute paths and compare expected/current virtual environment roots.
Tests:
- Activate different venv and verify mismatch warning then non-zero exit.

R015  Statement: Select requirements file by deterministic precedence.
Design: Use `requirements.txt` when present; otherwise use cpu/gpu split flow.
Tests:
- With `requirements.txt` present, verify split-file argument is not required.
- Without `requirements.txt`, verify split-file detection engages.

R020  Statement: Validate cpu/gpu selector when split requirements files are used.
Design: Require exactly one parameter and allow only `cpu` or `gpu`.
Tests:
- Run with missing selector and verify usage failure.
- Run with invalid selector and verify usage failure.

R025  Statement: Install dependencies via pip upgrade then requirements install.
Design: Enable `pip` alias to `pip3`, upgrade pip, then `pip install -r <selected-file>`.
Tests:
- Verify pip upgrade runs before requirements install.
- Verify selected requirements file is passed to pip install.

R030  Statement: Preserve manual traceability policy for locked script.
Constraints:
- `03_load_requirements.sh` is locked via `<AI_MODEL_INSTRUCTION>` and cannot be AI-edited.
- Traceability for this file is verified by exception policy, not inline `#R` tags.
Tests:
- Verify locked marker exists in script file.
- Verify batch traceability check reports `03` as policy exception, not failure.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for locked `03_load_requirements.sh`.
