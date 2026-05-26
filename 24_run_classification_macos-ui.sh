#!/usr/bin/env bash
#R001: Run in strict shell mode and fail fast.
set -euo pipefail
#R005: Resolve repository root from script location.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_path="$repo_root/src/macos-ui"
binary="$package_path/.build/debug/TransactionClassifier"
# Connect now runs in-process inside macos-ui (no localhost token server).
connect_api_url="inprocess://connect"
connect_manager_url="${TELLER_CONNECT_MANAGER_URL:-$connect_api_url}"

#R015: Optional transaction-list profiling via --profile.
profile_enabled=false
app_args=()
while (($# > 0)); do
    case "$1" in
        --profile)
            profile_enabled=true
            shift
            ;;
        -h|--help)
            cat <<'EOF'
usage: ./24_run_classification_macos-ui.sh [--profile] [app args...]

  --profile  Log transaction-list load and first-render timings to stderr
             ([teller-ui-profile] lines). Start the classifier API separately, e.g.:
             ./21_run_classification_api.py

  Other arguments are forwarded to TransactionClassifier.
EOF
            exit 0
            ;;
        *)
            app_args+=("$1")
            shift
            ;;
    esac
done

#R010: Forward all args to TransactionClassifier with package-path.
# Build synchronously so failures stop the script; launch the GUI detached from the TTY so
# keystrokes typed while using the app are not echoed into this terminal session.
if ! TELLER_CONNECT_API_URL="${connect_api_url}" \
     TELLER_CONNECT_MANAGER_URL="${connect_manager_url}" \
     swift build --package-path "$package_path" -c debug --product TransactionClassifier; then
  exit 1
fi

launch_env=(
    "TELLER_CONNECT_API_URL=${connect_api_url}"
    "TELLER_CONNECT_MANAGER_URL=${connect_manager_url}"
)
if [[ "$profile_enabled" == "true" ]]; then
    launch_env+=("TELLER_UI_PROFILE_TRANSACTION_LIST=true")
    echo "▶ Transaction list profiling enabled (stderr: [teller-ui-profile])" >&2
fi

if ((${#app_args[@]} > 0)); then
    env "${launch_env[@]}" "$binary" "${app_args[@]}" &
else
    env "${launch_env[@]}" "$binary" &
fi
exit 0
