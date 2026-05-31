#!/usr/bin/env bash
umask 007
set -euo pipefail

#R001: New pre-install integrity step runs before dependency installation.
#R005: Require the project virtual environment to exist and be active.
#R010: Compile hashed lockfiles from pip-tools source manifests.
#R015: Prepare SBOM + signing scaffold artifacts before install and test lanes.

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
cd "$REPO_ROOT"

CURRENT_DIRECTORY_NAME="$(basename "$(pwd)")"
VENV_DIR="${CURRENT_DIRECTORY_NAME}-venv"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "❌ ERROR: Virtual environment not found!"
  echo ""
  echo "Please run the virtual environment setup first:"
  echo "  ./02_create_venv.sh"
  exit 1
fi

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  echo "❌ ERROR: No virtual environment is currently active!"
  echo ""
  echo "Please activate the virtual environment first:"
  echo "  source $VENV_DIR/bin/activate"
  exit 1
fi

EXPECTED_VENV_PATH="$(cd "$VENV_DIR" && pwd -P)"
CURRENT_VENV_PATH="$(cd "${VIRTUAL_ENV:-}" && pwd -P 2>/dev/null || echo "${VIRTUAL_ENV:-}")"
if [[ "$CURRENT_VENV_PATH" != "$EXPECTED_VENV_PATH" ]]; then
  echo "❌ ERROR: Active virtual environment does not match project virtual environment."
  echo "Expected: $EXPECTED_VENV_PATH"
  echo "Current:  $CURRENT_VENV_PATH"
  exit 1
fi

RUNTIME_IN_FILE="${RUNTIME_IN_FILE:-./requirements.in}"
RUNTIME_LOCK_FILE="${RUNTIME_LOCK_FILE:-./requirements.txt}"
SECURITY_IN_FILE="${SECURITY_IN_FILE:-./requirements/security/requirements-security.in}"
SECURITY_LOCK_FILE="${SECURITY_LOCK_FILE:-./requirements/security/requirements-security.txt}"
SUPPLY_CHAIN_ARTIFACTS_DIR="${SUPPLY_CHAIN_ARTIFACTS_DIR:-./artifacts/security/reports}"
if [[ -z "${SUPPLY_CHAIN_SIGNING_MODE:-}" ]]; then
  if [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]; then
    SIGNING_MODE="required"
  else
    SIGNING_MODE="scaffold"
  fi
else
  SIGNING_MODE="${SUPPLY_CHAIN_SIGNING_MODE}"
fi

for file_path in "$RUNTIME_IN_FILE" "$SECURITY_IN_FILE"; do
  if [[ ! -f "$file_path" ]]; then
    echo "❌ Missing pip-tools source requirements file: $file_path"
    exit 1
  fi
done

echo "▶ Ensuring pip-tools is available"
if ! command -v pip-compile >/dev/null 2>&1; then
  echo "❌ ERROR: pip-compile is required but was not found on PATH."
  echo "Run ./01_install_prerequisites.sh to install Homebrew prerequisites."
  exit 1
fi
if python3 -m pip show pip-tools >/dev/null 2>&1; then
  echo "▶ Removing legacy venv pip-tools package to satisfy dependency-freshness gate"
  python3 -m pip uninstall -y pip-tools >/dev/null 2>&1 || true
fi

echo "▶ Compiling hash-pinned runtime lockfile (${RUNTIME_LOCK_FILE})"
pip-compile \
  --generate-hashes \
  --resolver=backtracking \
  --output-file "$RUNTIME_LOCK_FILE" \
  "$RUNTIME_IN_FILE"

echo "▶ Compiling hash-pinned security lockfile (${SECURITY_LOCK_FILE})"
pip-compile \
  --generate-hashes \
  --resolver=backtracking \
  --output-file "$SECURITY_LOCK_FILE" \
  "$SECURITY_IN_FILE"

echo "▶ Preparing SBOM + signing scaffold artifacts (${SUPPLY_CHAIN_ARTIFACTS_DIR})"
python3 ./src/scripts/security/generate_supply_chain_artifacts.py \
  --runtime-lock "$RUNTIME_LOCK_FILE" \
  --security-lock "$SECURITY_LOCK_FILE" \
  --output-dir "$SUPPLY_CHAIN_ARTIFACTS_DIR" \
  --signing-mode "$SIGNING_MODE"

echo "✅ Supply-chain integrity preparation completed."
