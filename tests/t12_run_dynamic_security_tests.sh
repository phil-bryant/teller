#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

#R001: Dynamic security lane wrapper remains the operator-facing entrypoint.
#R005: Wrapper resolves repository root from tests/ and delegates from repo context.
#R010: Delegates DAST toolchain bootstrap behavior to run_dynamic_security_lane.sh.
#R015: Delegates default RUN_DAST=true and RUN_SAST=false behavior to lane script.
#R020: Delegates completion/report output contract to lane script implementation.
#R025: Delegates DAST baseline/cleanup hygiene orchestration to lane script implementation.
#R030: Delegates ZAP summary + threshold gate behavior to lane script implementation.
#R035: Delegates strict Schemathesis findings gate (with optional downgrade toggle) to lane script implementation.
#R040: Delegates local API/Mailcart port-collision avoidance behavior to lane script implementation.
#R045: Delegates Schemathesis runtime-directory scoping to lane script implementation.
exec "${REPO_ROOT}/src/scripts/security/run_dynamic_security_lane.sh" "$@"
