#!/usr/bin/env bash
#R001: Run in strict mode and fail fast on key generation/export errors.
set -euo pipefail

#R005: Allow output/name/email/expiry customization via env vars and CLI flags.
OUTPUT_DIR="${OUTPUT_DIR:-./artifacts/security/backup-gpg}"
KEY_NAME="${BACKUP_GPG_KEY_NAME:-Teller Postgres Backup Encryption}"
KEY_EMAIL="${BACKUP_GPG_KEY_EMAIL:-backup-encryption@local.invalid}"
KEY_EXPIRY="${BACKUP_GPG_KEY_EXPIRY:-1y}"
PASSPHRASE="${BACKUP_GPG_KEY_PASSPHRASE:-}"

while (($#)); do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --name)
      KEY_NAME="${2:-}"
      shift 2
      ;;
    --email)
      KEY_EMAIL="${2:-}"
      shift 2
      ;;
    --expiry)
      KEY_EXPIRY="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--output-dir dir] [--name name] [--email email] [--expiry duration]" >&2
      exit 2
      ;;
  esac
done

if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg is required but was not found on PATH." >&2
  exit 1
fi

#R010: Require non-empty passphrase (prompt interactively when env override is absent).
if [[ -z "$PASSPHRASE" ]]; then
  read -r -s -p "Enter GPG private key passphrase: " PASSPHRASE
  echo
  read -r -s -p "Confirm passphrase: " PASSPHRASE_CONFIRM
  echo
  if [[ "$PASSPHRASE" != "$PASSPHRASE_CONFIRM" ]]; then
    echo "Passphrase confirmation did not match." >&2
    exit 1
  fi
fi

if [[ -z "$PASSPHRASE" ]]; then
  echo "Passphrase must be non-empty." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

TEMP_GNUPGHOME="$(mktemp -d)"
cleanup() {
  rm -rf "$TEMP_GNUPGHOME"
}
trap cleanup EXIT
chmod 700 "$TEMP_GNUPGHOME"

KEY_UID="${KEY_NAME} <${KEY_EMAIL}>"
#R015: Generate a dedicated encryption key and export armored public/private artifacts + metadata.
gpg --batch --yes --homedir "$TEMP_GNUPGHOME" --pinentry-mode loopback --passphrase "$PASSPHRASE" \
  --quick-gen-key "$KEY_UID" rsa4096 encrypt "$KEY_EXPIRY" >/dev/null

KEY_FINGERPRINT="$(
  gpg --batch --with-colons --homedir "$TEMP_GNUPGHOME" --list-keys "$KEY_UID" | awk -F: '$1=="fpr" {print $10; exit}'
)"
if [[ -z "$KEY_FINGERPRINT" ]]; then
  echo "Failed to resolve generated key fingerprint." >&2
  exit 1
fi

PUBLIC_KEY_PATH="${OUTPUT_DIR}/postgres-backup-public.asc"
PRIVATE_KEY_PATH="${OUTPUT_DIR}/postgres-backup-private.asc"
METADATA_PATH="${OUTPUT_DIR}/postgres-backup-key-metadata.txt"

gpg --batch --yes --armor --homedir "$TEMP_GNUPGHOME" --export "$KEY_FINGERPRINT" > "$PUBLIC_KEY_PATH"
gpg --batch --yes --armor --pinentry-mode loopback --passphrase "$PASSPHRASE" \
  --homedir "$TEMP_GNUPGHOME" --export-secret-keys "$KEY_FINGERPRINT" > "$PRIVATE_KEY_PATH"

chmod 600 "$PUBLIC_KEY_PATH" "$PRIVATE_KEY_PATH"
{
  echo "fingerprint=${KEY_FINGERPRINT}"
  echo "uid=${KEY_UID}"
  echo "expiry=${KEY_EXPIRY}"
} > "$METADATA_PATH"
chmod 600 "$METADATA_PATH"

echo "Generated backup encryption keys:"
echo "  public key : ${PUBLIC_KEY_PATH}"
echo "  private key: ${PRIVATE_KEY_PATH}"
echo "  metadata   : ${METADATA_PATH}"
echo
echo "1psa item: POSTGRES_BACKUP_ENCRYPTION"
echo "  type=gpg"
echo "  gpg_recipient=${KEY_FINGERPRINT}"
echo "  gpg_public_key=<contents of ${PUBLIC_KEY_PATH}>"
echo "  gpg_private_key=<contents of ${PRIVATE_KEY_PATH}>"
echo "  gpg_private_key_passphrase=<your passphrase>"
echo
echo ".env fallback variables:"
echo "  POSTGRES_BACKUP_ENCRYPTION_TYPE=gpg"
echo "  POSTGRES_BACKUP_ENCRYPTION_GPG_RECIPIENT=${KEY_FINGERPRINT}"
echo "  POSTGRES_BACKUP_ENCRYPTION_GPG_PUBLIC_KEY=<armored public key block>"
echo "  POSTGRES_BACKUP_ENCRYPTION_GPG_PRIVATE_KEY=<armored private key block>"
echo "  POSTGRES_BACKUP_ENCRYPTION_GPG_PRIVATE_KEY_PASSPHRASE=<your passphrase>"
