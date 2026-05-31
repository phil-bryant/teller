---
name: strict-clamav-stale-refresh
overview: Tighten AV signature freshness policy for t01 by reducing stale threshold to 24 hours and enforcing signature refresh whenever stale signatures are detected before scan execution.
todos:
  - id: update-t01-freshness-default
    content: Set default signature max age to 24h and add proactive stale-signature refresh flow in tests/t01_run_av_test.sh
    status: completed
  - id: add-bats-coverage-stale-refresh
    content: Add/adjust t01 bats tests for stale-triggered proactive freshclam and fresh-path no-refresh behavior
    status: completed
  - id: refresh-requirements-doc
    content: Update requirements/t01_run_av_test-requirements.md to codify strict stale refresh and 24h default
    status: completed
  - id: doc-alignment-readme
    content: Update README wording for t01 strict refresh behavior only if current wording is inaccurate
    status: completed
  - id: validate-targeted-tests
    content: Run focused t01 shell tests and verify strict freshness behavior and fallback retry behavior
    status: completed
isProject: false
---

# Enforce Strict ClamAV Freshness In t01

## Scope
Implement strict signature freshness behavior in the AV lane so stale signatures are always refreshed before scanning, with a default staleness threshold of 24 hours.

## Planned Changes
- Update [`/Users/phil/local/src/teller/tests/t01_run_av_test.sh`](/Users/phil/local/src/teller/tests/t01_run_av_test.sh):
  - Change default `CLAMAV_SIGNATURE_MAX_AGE_HOURS` from `48` to `24`.
  - Refactor signature freshness detection to return a machine-usable stale/fresh result (not only printed output).
  - If status is stale, run `freshclam --stdout` proactively before the first `clamscan` invocation.
  - Reuse existing freshclam error handling/bootstrap path (`ensure_freshclam_config`) for proactive refresh failures.
  - Keep existing missing-DB retry path as a fallback safety net, but avoid redundant freshclam calls when a proactive stale refresh already succeeded.

- Expand tests in [`/Users/phil/local/src/teller/tests/sh/t01_run_av_test.bats`](/Users/phil/local/src/teller/tests/sh/t01_run_av_test.bats):
  - Add/adjust a test that simulates stale signatures and verifies `freshclam --stdout` is called before scan.
  - Add coverage that confirms non-stale signatures do not trigger proactive refresh.
  - Keep existing missing-DB retry behavior tests passing.

- Update requirements in [`/Users/phil/local/src/teller/requirements/t01_run_av_test-requirements.md`](/Users/phil/local/src/teller/requirements/t01_run_av_test-requirements.md):
  - Revise freshness requirement language to include strict proactive refresh on stale signatures.
  - Record the new default freshness threshold (24h).

- Align docs wording in [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md) only if needed to reflect that t01 performs strict stale-signature refresh instead of only optional recovery.

## Validation
- Run AV shell tests targeting `t01` behavior (focused bats file) to verify:
  - stale signatures -> proactive refresh -> scan
  - fresh signatures -> no proactive refresh
  - missing DB path still retries once with refresh
- Confirm generated output messaging clearly indicates when stale signatures triggered enforced refresh.