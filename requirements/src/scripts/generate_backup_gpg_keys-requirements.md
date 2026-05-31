# Generate Backup GPG Keys Requirements

## Scope

Applies to `src/scripts/security/generate_backup_gpg_keys.sh`.

R001  Statement: Run the key-generation utility in strict shell mode.
Design: Use `set -euo pipefail` so argument parsing, gpg invocations, and export/write failures stop immediately.
Tests:
- R001-T01: Verify the script declares strict shell mode and exits non-zero for unknown arguments (`tests/sh/generate_backup_gpg_keys.bats`).

R005  Statement: Support configurable key metadata and output location.
Design: Accept `--output-dir`, `--name`, `--email`, and `--expiry` arguments (and matching env defaults) to customize generated key artifacts.
Tests:
- R005-T01: Verify the script includes all supported customization flags and corresponding default env vars (`tests/sh/generate_backup_gpg_keys.bats`).

R010  Statement: Require a non-empty passphrase for private-key export.
Design: Read passphrase from env or secure prompt, require confirmation for prompt mode, and fail when resulting passphrase is empty or mismatched.
Tests:
- R010-T01: Verify the script contains explicit non-empty passphrase enforcement and mismatch failure handling (`tests/sh/generate_backup_gpg_keys.bats`).

R015  Statement: Generate and export armored key artifacts with metadata for backup encryption bootstrap.
Design: Create temporary GNUPG home, generate an encryption key, export armored public/private keys, write metadata with fingerprint/uid/expiry, and print operator guidance for 1psa and `.env` fallback fields.
Tests:
- R015-T01: Verify the script includes key generation, armored export, metadata output, and 1psa/.env guidance emission (`tests/sh/generate_backup_gpg_keys.bats`).

## Changelog

- 2026-05-31: Initial requirements for backup GPG key generation utility.
