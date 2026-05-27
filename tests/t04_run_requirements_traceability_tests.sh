#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

cd "$REPO_ROOT"
#R001: Wrapper preserves strict shell-mode entrypoint contract for traceability checks.
#R005: Wrapper delegates all-requirements discovery behavior to Python traceability CLI.
#R010: Wrapper delegates source-resolution policy to Python traceability CLI.
#R015: Wrapper delegates explicit missing-file/mapping failures to Python traceability CLI.
#R020: Wrapper delegates requirements-ID parsing to Python traceability CLI.
#R025: Wrapper delegates #R tag parsing to Python traceability CLI.
#R030: Wrapper delegates set-difference reporting for missing/extra IDs.
#R035: Wrapper delegates aggregate pass/fail exit behavior to Python traceability CLI.
#R040: Wrapper delegates numbered script -> requirements coverage checks.
#R045: Wrapper delegates numbered requirements scope-alignment checks.
#R050: Wrapper delegates test-file discovery conventions to Python traceability CLI.
#R055: Wrapper delegates UI-lane requirement-ID classification checks.
#R060: Wrapper delegates per-lane test #R tag extraction checks.
#R065: Wrapper delegates requirement-to-test coverage enforcement checks.
#R070: Wrapper delegates anti-cheat and scoped #R comment enforcement checks.
#R075: Wrapper delegates requirements-only mode handling.
#R080: Wrapper delegates numbered script companion-test coverage checks.
#R085: Wrapper delegates repository software requirements-coverage checks.
#R090: Wrapper delegates numbered test-tag 1:1 enforcement checks.
exec env \
  PYTHONPATH="${REPO_ROOT}/tests/py${PYTHONPATH:+:${PYTHONPATH}}" \
  TRACEABILITY_EXCLUDE_SOURCE="$(basename "$0")" \
  python3 -m traceability.cli "$@"
