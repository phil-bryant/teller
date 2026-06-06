#!/usr/bin/env bash
# Thin wrapper pointer: sets RUNBOOK_REPO_ROOT + teller profile, execs the runner golden.
#R001: Enable secure umask and strict shell mode before delegation.
umask 007
set -euo pipefail
#R005: Resolve script and runner locations from the wrapper path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../../runner" && pwd -P)"
#R010: Export repo root context and load teller runbook profile.
RUNBOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
export RUNBOOK_REPO_ROOT
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/teller.env"
#R020: Preserve runner static-lane completion marker contract through passthrough delegation.
#R025: Preserve runner Ruff report artifact contract through passthrough delegation.
#R030: Preserve runner centralized SAST gate behavior through passthrough delegation.
#R035: Preserve runner scanner exclusion policy through passthrough delegation.
#R040: Preserve runner gitleaks tracked-source scan behavior through passthrough delegation.
#R045: Preserve runner Semgrep status visibility behavior through passthrough delegation.
#R047: Preserve runner unsuppressed Semgrep invocation contract through passthrough delegation.
#R050: Preserve runner Bandit status visibility behavior through passthrough delegation.
#R055: Preserve runner pip-audit status visibility behavior through passthrough delegation.
#R060: Preserve runner detect-secrets status visibility behavior through passthrough delegation.
#R065: Preserve runner Ruff status visibility behavior through passthrough delegation.
#R070: Preserve runner ShellCheck status visibility behavior through passthrough delegation.
#R080: Preserve runner cache-location behavior through passthrough delegation.
#R090: Preserve runner medium-or-higher blocking gate behavior through passthrough delegation.
#R100: Preserve runner token-redaction behavior through passthrough delegation.
#R105: Preserve runner hash-pinned toolchain enforcement through passthrough delegation.
#R110: Preserve runner supply-chain artifact generation behavior through passthrough delegation.
#R115: Preserve runner CI signing-mode default behavior through passthrough delegation.
#R420: Preserve runner static-lane finding-count behavior through passthrough delegation.
#R421: Preserve runner static-lane Semgrep formatter behavior through passthrough delegation.
#R422: Preserve runner static-lane hash-pin enforcement behavior through passthrough delegation.
#R423: Preserve runner static-lane supply-chain step behavior through passthrough delegation.
#R015: Delegate to the mapped runner golden with argument passthrough.
exec "${RUNNER_HOME}/tests/t03_run_static_security_tests.sh" "$@"
