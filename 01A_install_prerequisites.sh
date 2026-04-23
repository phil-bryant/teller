#!/bin/bash
umask 007

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ONEPSA_REPO_URL="https://github.com/phil-bryant/1psa.git"
ONEPSA_DIR="${PARENT_DIR}/1psa"
ONEPSA_LOCAL_BIN="${ONEPSA_DIR}/bin/1psa"
PG_INSTALL_REPO_URL="https://github.com/phil-bryant/pg_install"
PG_INSTALL_DIR="${PARENT_DIR}/pg_install"
PSA_INSTALL_SUDO_ITEM="${PSA_INSTALL_SUDO_ITEM:-odus}"

print_header() {
    echo "============================================================"
    echo "Prerequisites Installer"
    echo "============================================================"
    echo ""
}

ensure_homebrew() {
    echo "[Homebrew] Checking..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "❌ [Homebrew] Not installed."
        echo ""
        echo "Please install Homebrew first by running:"
        echo "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo ""
        echo "After installation, add Homebrew to your PATH and run this script again."
        echo "For more information, visit: https://brew.sh/"
        exit 1
    fi
    echo "✅ [Homebrew] Installed"
}

ensure_brew_formula() {
    FORMULA="$1"

    if command -v "$FORMULA" >/dev/null 2>&1; then
        echo "✅ [$FORMULA] Available on PATH"
        return
    fi

    echo "⚠️  [$FORMULA] Missing on PATH"
    echo "[${FORMULA}] Installing via Homebrew..."
    brew install "$FORMULA"

    if command -v "$FORMULA" >/dev/null 2>&1; then
        echo "✅ [$FORMULA] Installed and available"
    else
        echo "❌ [$FORMULA] Install completed but command still unavailable"
        exit 1
    fi
}

ensure_1psa() {
    echo ""
    echo "[1psa] Checking..."
    if command -v 1psa >/dev/null 2>&1; then
        echo "✅ [1psa] Available on PATH"
        return
    fi

    ensure_brew_formula "go"
    ensure_brew_formula "git"

    if [ ! -d "$ONEPSA_DIR" ]; then
        echo "[1psa] Cloning source into ${PARENT_DIR}..."
        git clone "$ONEPSA_REPO_URL" "$ONEPSA_DIR"
    else
        echo "✅ [1psa] Source directory already exists at ${ONEPSA_DIR}"
    fi

    if [ ! -f "${ONEPSA_DIR}/Makefile" ]; then
        echo "❌ [1psa] Missing Makefile in ${ONEPSA_DIR}"
        exit 1
    fi

    echo "[1psa] Building from source..."
    make -C "$ONEPSA_DIR"

    if [ ! -x "$ONEPSA_LOCAL_BIN" ]; then
        echo "❌ [1psa] Expected local binary missing at ${ONEPSA_LOCAL_BIN}"
        exit 1
    fi

    echo "[1psa] Installing with sudo credential from local 1psa item..."
    "$ONEPSA_LOCAL_BIN" -f "$PSA_INSTALL_SUDO_ITEM" "$PSA_INSTALL_SUDO_ITEM" | sudo -S make -C "$ONEPSA_DIR" install

    if command -v 1psa >/dev/null 2>&1; then
        echo "✅ [1psa] Installed and available on PATH"
    else
        echo "❌ [1psa] Install finished but command is still unavailable"
        exit 1
    fi
}

ensure_pg_install() {
    echo ""
    echo "[pg_install] Checking..."
    if [ -d "$PG_INSTALL_DIR/.git" ]; then
        echo "✅ [pg_install] Repository present at ${PG_INSTALL_DIR}"
    elif [ -e "$PG_INSTALL_DIR" ]; then
        echo "❌ [pg_install] ${PG_INSTALL_DIR} exists but is not a git repository"
        echo "Please remove or rename it, then run this script again."
        exit 1
    else
        ensure_brew_formula "git"
        echo "[pg_install] Cloning repository into ${PARENT_DIR}..."
        git clone "$PG_INSTALL_REPO_URL" "$PG_INSTALL_DIR"
        if [ -d "$PG_INSTALL_DIR/.git" ]; then
            echo "✅ [pg_install] Installed at ${PG_INSTALL_DIR}"
        else
            echo "❌ [pg_install] Clone step completed but repository was not found"
            exit 1
        fi
    fi
}

print_final_guidance() {
    echo ""
    echo "✅ All prerequisites are satisfied!"
    echo ""
    echo "Local prerequisite paths:"
    echo "- 1psa source: ${ONEPSA_DIR}"
    echo "- pg_install source: ${PG_INSTALL_DIR}"
}

print_header

ensure_homebrew

echo ""
echo "[Tooling] Checking build dependencies..."
ensure_brew_formula "go"
ensure_brew_formula "git"

ensure_1psa
ensure_pg_install
print_final_guidance
