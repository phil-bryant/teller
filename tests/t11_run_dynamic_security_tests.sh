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
#R020: Preserve runner dynamic-lane completion marker contract through passthrough delegation.
#R025: Preserve runner DAST baseline/cleanup behavior through passthrough delegation.
#R030: Preserve runner ZAP gate-threshold behavior through passthrough delegation.
#R035: Preserve runner Schemathesis blocking-mode behavior through passthrough delegation.
#R040: Preserve runner Mailcart/API port-collision handling through passthrough delegation.
#R045: Preserve runner Schemathesis report-dir execution behavior through passthrough delegation.
#R050: Preserve runner Schemathesis token-redaction behavior through passthrough delegation.
#R055: Preserve runner hash-pinned toolchain enforcement through passthrough delegation.
#R015: Delegate to the mapped runner golden with argument passthrough.
exec "${RUNNER_HOME}/tests/t09_run_dynamic_security_tests.sh" "$@"
