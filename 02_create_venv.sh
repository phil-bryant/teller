#!/bin/bash
umask 007

#R001: Fail fast on unrecoverable errors.
set -e

# Read Python version from prerequisites script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQ_SCRIPT="${SCRIPT_DIR}/01_install_prerequisites.sh"

#R005: Require sibling prerequisites script.
if [ ! -f "$PREREQ_SCRIPT" ]; then
    echo "❌ ERROR: Prerequisites script not found: $PREREQ_SCRIPT"
    echo "Please ensure 01_install_prerequisites.sh is in the same directory."
    exit 1
fi

PYTHON_BIN=""
#R010: Prefer python3.12, fallback to python3.
if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="python3.12"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
fi

#R015: Fail if no supported interpreter is available.
if [ -z "$PYTHON_BIN" ]; then
    echo "❌ ERROR: No suitable Python interpreter found (tried python3.12, python3)."
    exit 1
fi

#R020: Name venv as <cwd-basename>-venv.
CURRENT_DIRECTORY_NAME=$(basename "$(pwd)")
VENV_DIR="${CURRENT_DIRECTORY_NAME}-venv"

#R025: Refuse creation while another virtual environment is active.
if [ -n "$VIRTUAL_ENV" ]; then
    echo "❌ ERROR: A virtual environment is currently active!"
    echo ""
    echo "Please deactivate first by running:"
    echo "  deactivate"
    echo ""
    echo "Then run this script again."
    exit 1
fi

#R030: Keep venv creation idempotent.
if [ -d "$VENV_DIR" ]; then
    echo "✓ Virtual environment already exists: $VENV_DIR"
    echo ""
    echo "To activate the virtual environment, run:"
    echo "  activate"
    exit 0
fi

#R035: Create venv with selected interpreter.
echo "Creating virtual environment..."
"$PYTHON_BIN" -m venv "$VENV_DIR"

#R040: Print activation guidance after successful runs.
echo "✓ Created virtual environment: $VENV_DIR"
echo ""
echo "To activate the virtual environment, run:"
echo "  activate"