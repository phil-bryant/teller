# Configure Teller.io Requirements

## Scope

Applies to `05_configure_teller_io.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- Verify script exits on unset variable and failed command paths.

R005  Statement: Ensure Teller config directory exists with restricted permissions.
Design: Create `~/.teller` and enforce mode `700`.
Tests:
- Remove directory, run script, verify directory is recreated with mode `700`.

R010  Statement: Optionally provision Teller examples repository.
Design: Clone examples when enabled, skip when `CONFIGURE_TELLER_EXAMPLES!=true`.
Constraints:
- Existing non-git path at destination is an error.
Tests:
- Run with default settings and verify clone when missing.
- Run with `CONFIGURE_TELLER_EXAMPLES=false` and verify skip output.

R015  Statement: Provision application id from file, env, or 1psa.
Design: Prefer existing file, then `TELLER_APPLICATION_ID`, then 1psa item/field.
Constraints:
- Output file must be mode `400`.
Tests:
- Remove file, set `TELLER_APPLICATION_ID`, verify file creation and mode `400`.

R020  Statement: Provision certificate and private key from file paths or 1psa.
Design: Reuse existing files when present, else copy from env paths or write from 1psa.
Constraints:
- Cert/key files must be mode `400`.
Tests:
- Supply `TELLER_CERT_PATH`/`TELLER_KEY_PATH` and verify copied files with mode `400`.

R025  Statement: Optionally provision auth token json from env or 1psa.
Design: Create `auth_token.json` with `{\"current\":\"...\"}` when token source provided.
Constraints:
- Auth token file must be mode `400`.
Tests:
- Set `TELLER_ACCESS_TOKEN` and verify json output and mode `400`.

R030  Statement: Perform mandatory institutions API smoke test with mTLS.
Design: Call `/institutions` with cert/key, require HTTP 200.
Tests:
- Use invalid cert/key and verify non-zero exit with response details.

R035  Statement: Perform optional accounts API smoke test when auth token exists.
Design: Call `/accounts` with token; warn on non-200 without hard failure.
Tests:
- Provide stale token and verify warning plus troubleshooting guidance.

R040  Statement: Print final readiness summary with configured file inventory.
Design: Output ready status, repo path, and created Teller file list.
Tests:
- Verify successful run prints directory and file summary.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `05_configure_teller_io.sh`.
