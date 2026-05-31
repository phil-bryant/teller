# Generate Supply-Chain Artifacts Requirements

## Scope

Applies to `src/scripts/security/generate_supply_chain_artifacts.py`.

R110  Statement: Generate SBOM and signing scaffold artifacts from lockfiles.
Design: Parse runtime/security lockfiles and emit `sbom.cdx.json`, `sbom.signature`, and `sbom.attestation.json`; support scaffold signature mode when cosign/key context is not configured.
Tests:
- R110-T01: Run generator with sample lockfiles and verify SBOM, signature, and attestation artifacts are written.

## Changelog

- 2026-05-30: Initial requirements for supply-chain artifact generation script.
