#!/usr/bin/env bash
# Thin pointer: selects the teller runbook profile and delegates to the runner golden via the shared shim.
#R001: Secure umask and strict shell mode are centralized in pointer_shim.sh.
#R005: RUNNER_HOME and RUNBOOK_REPO_ROOT resolution are centralized in pointer_shim.sh.
#R010: Pointer selects its runbook profile; the shim sources the matching runner/config/runbook profile and exports RUNBOOK_REPO_ROOT.
RUNBOOK_PROFILE="teller"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../runner/src/scripts" && pwd -P)/pointer_shim.sh"
#R015: Delegate to the mapped runner golden with argument passthrough.
delegate_golden "99_restore_database.sh" "$@"
