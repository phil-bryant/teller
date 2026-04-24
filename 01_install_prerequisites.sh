#!/bin/bash
umask 007

#R001: Run with bash and fail fast on unrecoverable errors.
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ONEPSA_REPO_URL="https://github.com/phil-bryant/1psa.git"
ONEPSA_DIR="${PARENT_DIR}/1psa"
ONEPSA_LOCAL_BIN="${ONEPSA_DIR}/bin/1psa"
PG_INSTALL_REPO_URL="https://github.com/phil-bryant/pg_install"
PG_INSTALL_DIR="${PARENT_DIR}/pg_install"
ZAP_APP_PATH="${ZAP_APP_PATH:-/Applications/ZAP.app}"
ZAP_CLI_PATH="${ZAP_CLI_PATH:-${ZAP_APP_PATH}/Contents/MacOS/ZAP.sh}"
#R020: Default sudo credential item/field, overridable via environment.
PSA_INSTALL_SUDO_ITEM="${PSA_INSTALL_SUDO_ITEM:-odus}"

print_header() {
    echo "============================================================"
    echo "Prerequisites Installer"
    echo "============================================================"
    echo ""
}

ensure_homebrew() {
    #R005: Verify Homebrew is present before package actions.
    #R035: Emit explicit status lines for this prerequisite phase.
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
    #R012 #R030: Ensure required brew formulas (go/git) are available.
    #R035 #R040: Print status and skip install when already available.
    FORMULA="$1"
    COMMAND_NAME="${2:-$FORMULA}"

    if command -v "$COMMAND_NAME" >/dev/null 2>&1; then
        echo "✅ [$FORMULA] Available on PATH"
        return
    fi

    echo "⚠️  [$FORMULA] Missing on PATH"
    echo "[${FORMULA}] Installing via Homebrew..."
    brew install "$FORMULA"

    if command -v "$COMMAND_NAME" >/dev/null 2>&1; then
        echo "✅ [$FORMULA] Installed and available"
    else
        echo "❌ [$FORMULA] Install completed but command still unavailable"
        exit 1
    fi
}

ensure_zap_cli() {
    #R070: Ensure local OWASP ZAP CLI is installed via Homebrew cask when missing.
    #R075: Verify expected CLI wrapper path after install.
    #R035 #R040: Emit status lines and keep phase idempotent.
    echo ""
    echo "[ZAP] Checking..."

    if [ -x "$ZAP_CLI_PATH" ]; then
        echo "✅ [ZAP] CLI available at ${ZAP_CLI_PATH}"
        return
    fi

    echo "⚠️  [ZAP] CLI wrapper missing at ${ZAP_CLI_PATH}"
    echo "[ZAP] Installing Homebrew cask 'zap'..."
    brew install --cask zap

    if [ -x "$ZAP_CLI_PATH" ]; then
        echo "✅ [ZAP] Installed and CLI available at ${ZAP_CLI_PATH}"
    else
        echo "❌ [ZAP] Install completed but CLI wrapper is still missing at ${ZAP_CLI_PATH}"
        echo "Open ZAP.app once if macOS blocked first launch, then rerun this script."
        exit 1
    fi
}

ensure_1psa() {
    #R010: Ensure 1psa is available on PATH.
    #R035: Print explicit status for the 1psa phase.
    echo ""
    echo "[1psa] Checking..."
    if command -v 1psa >/dev/null 2>&1; then
        #R040: Idempotent reruns skip re-install when requirement is already met.
        echo "✅ [1psa] Available on PATH"
        return
    fi

    #R012: Ensure Go and Git prerequisites before clone/build.
    ensure_brew_formula "go"
    ensure_brew_formula "git"

    #R010: Clone 1psa source when sibling tree is missing.
    if [ ! -d "$ONEPSA_DIR" ]; then
        echo "[1psa] Cloning source into ${PARENT_DIR}..."
        git clone "$ONEPSA_REPO_URL" "$ONEPSA_DIR"
    else
        echo "✅ [1psa] Source directory already exists at ${ONEPSA_DIR}"
    fi

    #R010: Require upstream Makefile before build/install.
    if [ ! -f "${ONEPSA_DIR}/Makefile" ]; then
        echo "❌ [1psa] Missing Makefile in ${ONEPSA_DIR}"
        exit 1
    fi

    #R015: Build using upstream Makefile target.
    echo "[1psa] Building from source..."
    make -C "$ONEPSA_DIR"

    if [ ! -x "$ONEPSA_LOCAL_BIN" ]; then
        echo "❌ [1psa] Expected local binary missing at ${ONEPSA_LOCAL_BIN}"
        exit 1
    fi

    #R020 #R045: Use runtime 1psa lookup for sudo credential; no hardcoded secret.
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
    #R025: Ensure pg_install repository exists and is verifiable.
    #R035: Print explicit status for the pg_install phase.
    echo ""
    echo "[pg_install] Checking..."
    if [ -d "$PG_INSTALL_DIR/.git" ]; then
        #R040: Idempotent reruns skip clone when repository already exists.
        echo "✅ [pg_install] Repository present at ${PG_INSTALL_DIR}"
    elif [ -e "$PG_INSTALL_DIR" ]; then
        echo "❌ [pg_install] ${PG_INSTALL_DIR} exists but is not a git repository"
        echo "Please remove or rename it, then run this script again."
        exit 1
    else
        #R030: Ensure git exists before clone operations.
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

ensure_xcode_ready() {
    #R060: Ensure xcodebuild exists and Xcode first-launch setup is complete.
    #R065: Use 1psa-provided sudo credential for privileged Xcode initialization.
    echo ""
    echo "[Xcode] Checking..."
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "❌ [Xcode] xcodebuild not found."
        echo "Install Xcode (or Command Line Tools) and run this script again."
        echo "Tip: xcode-select --install"
        exit 1
    fi

    if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        echo "✅ [Xcode] First-launch status already configured"
        return
    fi

    echo "⚠️  [Xcode] First-launch setup required; running with sudo..."
    sudo -k
    "$ONEPSA_LOCAL_BIN" -f "$PSA_INSTALL_SUDO_ITEM" "$PSA_INSTALL_SUDO_ITEM" | sudo -S xcodebuild -runFirstLaunch

    # Some Xcode installations still require explicit license acceptance.
    if ! xcodebuild -license check >/dev/null 2>&1; then
        echo "⚠️  [Xcode] Accepting Xcode license..."
        sudo -k
        "$ONEPSA_LOCAL_BIN" -f "$PSA_INSTALL_SUDO_ITEM" "$PSA_INSTALL_SUDO_ITEM" | sudo -S xcodebuild -license accept
    fi

    if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        echo "✅ [Xcode] First-launch setup completed"
    else
        echo "❌ [Xcode] First-launch setup did not complete successfully"
        exit 1
    fi
}

print_final_guidance() {
    #R050: Print final readiness guidance and local source paths.
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
#R055: Ensure bats shell test runner dependency is installed via Homebrew.
ensure_brew_formula "bats-core" "bats"
ensure_zap_cli

ensure_1psa
ensure_xcode_ready
ensure_pg_install
print_final_guidance
