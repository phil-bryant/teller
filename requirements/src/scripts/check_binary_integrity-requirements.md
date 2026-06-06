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

R200  Statement: Normalize a hex digest to lowercase canonical form, rejecting non-hex input.
Design: Normalize digests with strict hex validation and canonical lowercase output.
Tests:
- R200-T01: Verify hex normalization lowercases valid input and rejects non-hex values.

R201  Statement: Parse and validate one policy entry into a BinaryPolicy.
Design: Validate command/version/hash fields and build BinaryPolicy records.
Tests:
- R201-T01: Verify malformed policy entries raise and valid entries parse into BinaryPolicy.

R202  Statement: Load policy JSON into an ordered list of validated policies.
Design: Read policy JSON, validate binaries list shape, and parse each entry.
Tests:
- R202-T01: Verify policy loader returns validated entries in configured order.

R203  Statement: Resolve a command name to an absolute executable path or None.
Design: Resolve direct paths and PATH lookups with executability checks.
Tests:
- R203-T01: Verify executable resolution for present absolute and PATH commands.

R204  Statement: Execute a version-probe subprocess and capture output safely.
Design: Run version command with timeout and execution error handling.
Tests:
- R204-T01: Verify version probe returns output on success and error diagnostics on failure.

R205  Statement: Extract a version string from probe output via regex.
Design: Apply configured regex with safe fallback for bad patterns/no matches.
Tests:
- R205-T01: Verify version parsing for matching, non-matching, and invalid regex patterns.

R206  Statement: Compare current vs minimum version, returning sign or None when unknown.
Design: Compare normalized versions and return ordering with unknown fallback.
Tests:
- R206-T01: Verify version comparison ordering and unknown behavior for unparsable versions.

R207  Statement: Compute the SHA256 digest of a file.
Design: Read file bytes in chunks and emit deterministic SHA256 hex digests.
Tests:
- R207-T01: Verify digest helper returns expected hash shape and deterministic value.

R208  Statement: Summarize per-binary statuses into missing/stale/mismatch counters.
Design: Aggregate status classes into summary counter fields.
Tests:
- R208-T01: Verify summary counters reflect mixed missing/stale/mismatch statuses.

R209  Statement: Parse CLI arguments for policy path and strict gate flags.
Design: Define parser defaults/options for outputs and strict failure switches.
Tests:
- R209-T01: Verify parse_args exposes configured policy/output/strict flags.
