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

## Changelog

- 2026-05-30: Initial requirements for supply-chain artifact generation script.
- 2026-05-31: Added scanner-ingestible SBOM component metadata requirements (`purl`, `hashes[]`, `licenses[]`).
- 2026-05-31: Added keyless-cosign CI signing requirements (R120).
