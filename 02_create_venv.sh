#!/bin/bash
umask 007

set -e

# Read Python version from prerequisites script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQ_SCRIPT="${SCRIPT_DIR}/01_install_prerequisites.sh"

if [ ! -f "$PREREQ_SCRIPT" ]; then
    echo "❌ ERROR: Prerequisites script not found: $PREREQ_SCRIPT"
    echo "Please ensure 01_install_prerequisites.sh is in the same directory."
    exit 1
fi

# Extract Python version from prerequisites script
PYTHON_VERSION=$(grep '^PYTHON_VERSION=' "$PREREQ_SCRIPT" | cut -d'"' -f2)

if [ -z "$PYTHON_VERSION" ]; then
    echo "❌ ERROR: Could not determine Python version from prerequisites script"
    exit 1
fi

# Check if the required Python version is installed
if ! command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
    echo "❌ ERROR: Python ${PYTHON_VERSION} is not installed."
    echo ""
    echo "Please run the prerequisites script first:"
    echo "  ./01_install_prerequisites.sh"
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
python${PYTHON_VERSION} -m venv "$VENV_DIR"

echo "✓ Created virtual environment: $VENV_DIR"
echo ""
echo "To activate the virtual environment, run:"
echo "  activate"