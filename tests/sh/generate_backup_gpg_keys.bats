#!/usr/bin/env bats

load "helpers/common.bash"

@test "script defines strict mode and rejects unknown args" {
  #R001-T01
  run grep 'set -euo pipefail' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]

  run bash "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh" --not-a-real-flag
  [ "$status" -eq 2 ]
}

@test "script exposes expected customization flags and env defaults" {
  #R005-T01
  run grep 'OUTPUT_DIR="\${OUTPUT_DIR:-\./artifacts/security/backup-gpg}"' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep 'KEY_NAME="\${BACKUP_GPG_KEY_NAME:-Teller Postgres Backup Encryption}"' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep 'KEY_EMAIL="\${BACKUP_GPG_KEY_EMAIL:-backup-encryption@local.invalid}"' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep 'KEY_EXPIRY="\${BACKUP_GPG_KEY_EXPIRY:-1y}"' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep -- '--output-dir' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep -- '--name' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep -- '--email' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep -- '--expiry' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
}

@test "script enforces non-empty passphrase handling" {
  #R010-T01
  run grep 'Passphrase confirmation did not match' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep 'Passphrase must be non-empty' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
}

@test "script contains key generation, export, metadata and guidance output" {
  #R015-T01
  run grep -- '--quick-gen-key' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep -- '--export-secret-keys' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep 'fingerprint=\${KEY_FINGERPRINT}' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep '1psa item: POSTGRES_BACKUP_ENCRYPTION' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
  run grep '.env fallback variables:' "$(repo_root)/src/scripts/security/generate_backup_gpg_keys.sh"
  [ "$status" -eq 0 ]
}
