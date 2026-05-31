# Check Binary Integrity Requirements

## Scope

Applies to `src/scripts/check_binary_integrity.py`.

R001  Statement: Collect binary executable path/version/hash metadata from policy-defined command entries.
Design: Load policy JSON entries, resolve executable paths, run version probes, parse versions via regex, and compute SHA256 file digests.
Tests:
- R001-T01: Evaluate a policy with present and missing commands and verify report includes executable path, version, and hash fields (`tests/py/test_check_binary_integrity.py`).

R005  Statement: Emit machine-readable and human-readable binary integrity reports.
Design: Write JSON and text outputs with summary counters plus per-binary status rows.
Tests:
- R005-T01: Verify report generation counts missing required and stale-version statuses correctly (`tests/py/test_check_binary_integrity.py`).

R010  Statement: Enforce optional strict gates for missing required binaries, version policy failures, and hash mismatches.
Design: Return non-zero when `--fail-on-missing-required` detects missing required commands, when `--fail-on-version` detects stale/unknown constrained versions, or when `--fail-on-hash` detects checksum mismatches.
Tests:
- R010-T01: Verify `main()` returns failing exit status only when the corresponding strict gate is enabled and its condition is present (`tests/py/test_check_binary_integrity.py`).

R015  Statement: Maintain SHA256 allowlists for pinned binaries with a documented refresh workflow.
Design: Pin high-sensitivity local binaries in `config/security/binary-integrity-policy.json` (currently `1psa`, `cosign`, and `gitleaks`) and treat `--fail-on-hash` mismatches as blocking in strict lanes. For intentionally upgraded binaries, refresh digest pins by rerunning the integrity checker, copying observed digests into `allowed_sha256`, and rerunning t02 before merging. Homebrew-managed binaries may churn digests on upgrade, so pin selectively and only update hashes for deliberate upgrades.
Tests:
- R015-T01: Verify a digest in `allowed_sha256` produces an `ok` hash status and no hash mismatch count (`tests/py/test_check_binary_integrity.py`).
