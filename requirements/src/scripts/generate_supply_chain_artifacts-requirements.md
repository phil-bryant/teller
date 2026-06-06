# Generate Supply-Chain Artifacts Requirements

## Scope

Applies to `src/scripts/security/generate_supply_chain_artifacts.py`.

R110  Statement: Generate SBOM and signing scaffold artifacts from lockfiles.
Design: Parse runtime/security lockfiles and emit `sbom.cdx.json`, `sbom.signature`, and `sbom.attestation.json`; support scaffold signature mode when cosign/key context is not configured.
Tests:
- R110-T01: Run generator with sample lockfiles and verify SBOM, signature, and attestation artifacts are written.

R115  Statement: Emit scanner-ingestible CycloneDX component metadata.
Design: Parse lockfile package blocks with `--hash=sha256:...`, map each pinned dependency to a CycloneDX component with `bom-ref`, `purl`, `scope`, and `hashes[]`, and enrich `licenses[]` from the matching PyPI release metadata with a safe unknown-license fallback when metadata is unavailable.
Tests:
- R115-T01: Verify generated SBOM components include `purl`, SHA256 hash entries, and non-empty `licenses[]` metadata for runtime and security dependencies (`tests/py/test_generate_supply_chain_artifacts.py`).

R120  Statement: Support cosign keyless signing in CI while preserving local key/scaffold behavior.
Design: Attempt key-based cosign signing when `COSIGN_KEY` is set; in GitHub Actions CI without `COSIGN_KEY`, attempt keyless OIDC signing and fail `required` mode when signing context is unavailable; retain scaffold output only for non-required flows.
Tests:
- R120-T01: Verify required signing mode fails with a clear context error when neither key-based nor keyless signing context is available (`tests/py/test_generate_supply_chain_artifacts.py`).

R400  Statement: Compute the SHA256 digest of a file.
Design: Stream file bytes through SHA256 and return the lowercase hex digest string.
Tests:
- R400-T01: Verify `sha256_file` returns the expected digest for known bytes (`tests/py/test_generate_supply_chain_artifacts.py`).

R401  Statement: Serialize a payload to JSON on disk deterministically.
Design: Persist payloads using stable indentation and a trailing newline for reproducible artifacts.
Tests:
- R401-T01: Verify `write_json` writes deterministic indented JSON with a trailing newline (`tests/py/test_generate_supply_chain_artifacts.py`).

R402  Statement: Probe whether an external command is available on PATH.
Design: Run a shell `command -v` probe and return success/failure as a boolean.
Tests:
- R402-T01: Verify `has_command` returns true for an available interpreter and false for a missing command (`tests/py/test_generate_supply_chain_artifacts.py`).

R403  Statement: Normalize a PyPI package name to canonical (PEP-503) form.
Design: Lowercase package names and collapse separator runs (`-`, `_`, `.`) into single hyphens.
Tests:
- R403-T01: Verify `normalize_pypi_name` canonicalizes mixed-case separator-heavy names (`tests/py/test_generate_supply_chain_artifacts.py`).

R404  Statement: Build a Package-URL (purl) from name/version.
Design: Use normalized package names and version pins to emit `pkg:pypi/<name>@<version>`.
Tests:
- R404-T01: Verify `build_purl` emits `pkg:pypi` references with normalized names (`tests/py/test_generate_supply_chain_artifacts.py`).

R405  Statement: Derive an SPDX license id from trove classifiers.
Design: Map known classifier strings to SPDX identifiers and return null when no mapping applies.
Tests:
- R405-T01: Verify `_license_id_from_classifiers` maps known classifiers and returns null for unknown classifiers (`tests/py/test_generate_supply_chain_artifacts.py`).

R406  Statement: Parse a hash-pinned requirements file into pinned specs.
Design: Read requirement lines with `name==version` and collect associated `--hash=sha256` pins per component.
Tests:
- R406-T01: Verify `parse_pinned_requirements` returns pinned components and normalized hash lists (`tests/py/test_generate_supply_chain_artifacts.py`).

R407  Statement: Assemble a CycloneDX SBOM document from parsed inputs.
Design: Build CycloneDX metadata plus component entries containing purl, scope, hashes, and licenses.
Tests:
- R407-T01: Verify `build_cyclonedx` emits required top-level metadata and component fields (`tests/py/test_generate_supply_chain_artifacts.py`).

R408  Statement: Merge and de-duplicate SBOM components by identity.
Design: Coalesce duplicate normalized name/version tuples and upgrade scope/hash unions deterministically.
Tests:
- R408-T01: Verify `merge_components` collapses duplicates and preserves required scope precedence (`tests/py/test_generate_supply_chain_artifacts.py`).

R409  Statement: Sign a blob with cosign, capturing output safely.
Design: Execute a non-interactive cosign invocation, capture output, and report success only when the signature artifact is present.
Tests:
- R409-T01: Verify `_run_cosign_sign_blob` succeeds only when subprocess invocation returns zero and writes a signature file (`tests/py/test_generate_supply_chain_artifacts.py`).

R410  Statement: Write a detached scaffold signature artifact.
Design: Emit a deterministic key-value scaffold payload including mode, SBOM hash, and reason fields.
Tests:
- R410-T01: Verify `write_scaffold_signature` writes scaffold mode, digest, and reason values (`tests/py/test_generate_supply_chain_artifacts.py`).

R411  Statement: Orchestrate SBOM build, signing flow, and exit-code policy.
Design: Parse CLI args, validate lockfiles, build artifacts, enforce signing-mode behavior, and return process exit status.
Tests:
- R411-T01: Verify required signing mode returns non-zero when no usable cosign context is available (`tests/py/test_generate_supply_chain_artifacts.py`).

## Changelog

- 2026-05-30: Initial requirements for supply-chain artifact generation script.
- 2026-05-31: Added scanner-ingestible SBOM component metadata requirements (`purl`, `hashes[]`, `licenses[]`).
- 2026-05-31: Added keyless-cosign CI signing requirements (R120).
- 2026-06-06: Added fine-grained SBOM requirement IDs R400-R411 with one anchored test per behavior.
