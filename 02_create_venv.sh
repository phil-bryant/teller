#!/bin/bash
umask 007

set -e

# Read Python version from prerequisites script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQ_SCRIPT="${SCRIPT_DIR}/01A_install_prerequisites.sh"

if [ ! -f "$PREREQ_SCRIPT" ]; then
    echo "❌ ERROR: Prerequisites script not found: $PREREQ_SCRIPT"
    echo "Please ensure 01A_install_prerequisites.sh is in the same directory."
    exit 1
fi

PYTHON_BIN=""
if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="python3.12"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
fi

if [ -z "$PYTHON_BIN" ]; then
    echo "❌ ERROR: No suitable Python interpreter found (tried python3.12, python3)."
    exit 1
fi

CURRENT_DIRECTORY_NAME=$(basename "$(pwd)")
VENV_DIR="${CURRENT_DIRECTORY_NAME}-venv"

# Check for active virtual environment and exit if found
if [ -n "$VIRTUAL_ENV" ]; then
    echo "❌ ERROR: A virtual environment is currently active!"
    echo ""
    echo "Please deactivate first by running:"
    echo "  deactivate"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Check if venv already exists
if [ -d "$VENV_DIR" ]; then
    echo "✓ Virtual environment already exists: $VENV_DIR"
    echo ""
    echo "To activate the virtual environment, run:"
    echo "  activate"
    exit 0
fi

echo "Creating virtual environment..."
"$PYTHON_BIN" -m venv "$VENV_DIR"

echo "✓ Created virtual environment: $VENV_DIR"
echo ""
echo "To activate the virtual environment, run:"
echo "  activate"