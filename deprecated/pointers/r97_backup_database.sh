#!/usr/bin/env bash
# Thin runbook pointer: sets RUNBOOK_REPO_ROOT + teller profile, execs the runner golden.
umask 007
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../runner" && pwd)"
export RUNBOOK_REPO_ROOT="$SCRIPT_DIR"
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/teller.env"
exec "${RUNNER_HOME}/97_backup_database.sh" "$@"
