# Run Teller Live Canary Requirements

## Scope

Applies to `tests/t17_run_teller_live_canary_test.sh`.

## Ownership Boundaries

This document owns strict live-canary wrapper orchestration behavior.
Canary implementation details are owned by:
- `requirements/src/scripts/check_teller_api_drift-requirements.md`

R001  Statement: Resolve repository root from script path before launching live canary checks.
Design: Resolve script directory via `${BASH_SOURCE[0]}` and `cd` to repo root so script works from any caller CWD.
Tests:
- R001-T01: Verify script contains repository-root resolution and invokes the live canary script via repo-relative path.

R005  Statement: Enforce strict live-only canary semantics.
Design: Invoke `check_teller_api_drift.py` with `--require-live` and `--fail-on-warn` so fallback mode and warning status fail this lane.
Tests:
- R005-T01: Verify wrapper passes both strict flags to the live canary command.
