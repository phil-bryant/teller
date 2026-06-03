#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

#R001: Static security lane wrapper remains the operator-facing entrypoint.
#R005: Wrapper resolves repository root from tests/ and delegates from repo context.
#R010: Delegates security toolchain bootstrap behavior to run_static_security_lane.sh.
#R015: Delegates default RUN_SAST=true and RUN_DAST=false behavior to lane script.
#R020: Delegates completion/report output contract to lane script implementation.
#R025: Delegates Ruff execution and report contract to lane script implementation.
#R030: Delegates Ruff gate behavior to lane script implementation.
#R035: Delegates detect-secrets exclusion policy to lane script implementation.
#R040: Delegates gitleaks tracked-source snapshot policy to lane script implementation.
#R045: Delegates Semgrep detailed status output to lane script implementation.
#R047: Delegates Semgrep no-quiet invocation contract to lane script implementation.
#R050: Delegates Bandit detailed status output to lane script implementation.
#R055: Delegates pip-audit detailed status output to lane script implementation.
#R060: Delegates detect-secrets detailed status output to lane script implementation.
#R065: Delegates Ruff detailed status output to lane script implementation.
#R070: Delegates ShellCheck detailed status output to lane script implementation.
#R080: Delegates cache-location policy (__pycache__ under artifacts/cache) to lane script implementation.
#R090: Delegates medium-or-higher blocking policy to lane script implementation.
#R100: Delegates Schemathesis token-redaction persistence policy to lane script implementation.
#R105: Delegates hash-pinned requirements enforcement to lane script implementation.
#R110: Delegates SBOM/signing scaffold artifact emission to lane script implementation.
#R115: Delegates CI-default required SBOM signing-mode behavior to lane script implementation.
exec "${REPO_ROOT}/src/scripts/security/run_static_security_lane.sh" "$@"
