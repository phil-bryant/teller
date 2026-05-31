---
name: hash-pin-and-sbom-signing
overview: Add a new pre-03 numbered operator step for pip-tools lock/SBOM/signing prep, keep install-time integrity in 03 via hashed lockfiles, and enforce verification in security/test lanes.
todos:
  - id: renumber-03-13-to-04-14
    content: Renumber operator scripts 03-13 to 04-14 and insert new 03 integrity-prep script with fully consistent references
    status: completed
  - id: add-pip-tools-lock-workflow
    content: Add .in sources and hashed pip-compile lock outputs for runtime and security dependencies
    status: completed
  - id: enforce-require-hashes
    content: Update security lane install commands to require hashes and fail clearly on missing hash data
    status: completed
  - id: add-sbom-signing-lane-step
    content: Add SBOM generation plus signing/attestation scaffold and wire into static security lane
    status: completed
  - id: extend-supply-chain-tests
    content: Update BATS/tests to assert --require-hashes, SBOM artifact creation, and signing scaffold behavior
    status: completed
  - id: update-docs-and-traceability
    content: Update README and requirements traceability docs for new supply-chain controls
    status: completed
isProject: false
---

# Raise Supply-Chain Integrity To 9+

## Goal
Close the two remaining high-impact gaps you identified with strict numbered operator sequencing:
- renumber existing scripts **03-13 -> 04-14** and inject a new **03** integrity-prep step
- add a **new numbered pre-03 step** that prepares/refreshes hashed lockfiles and SBOM/signing inputs
- enforce **hash-pinned installs** at install time in `03` by installing from hashed lockfiles
- add **SBOM + signing/attestation scaffolding** to the security/CI verification path

## Current-State Findings
- Runtime and security deps are version-pinned but not hash-pinned in [`/Users/phil/local/src/teller/requirements.txt`](/Users/phil/local/src/teller/requirements.txt) and [`/Users/phil/local/src/teller/requirements/security/requirements-security.txt`](/Users/phil/local/src/teller/requirements/security/requirements-security.txt).
- Security lanes currently install with plain `pip install -r ...` in [`/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh) and [`/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh).
- There is no SBOM or signing flow in the current test/security entrypoints (e.g. [`/Users/phil/local/src/teller/tests/t03_run_static_security_tests.sh`](/Users/phil/local/src/teller/tests/t03_run_static_security_tests.sh)).
- [`/Users/phil/local/src/teller/04_load_requirements.sh`](/Users/phil/local/src/teller/04_load_requirements.sh) is explicitly locked from AI edits, so we should not depend on changing it for this pass.

## Implementation Plan

### 0) Renumber operator sequence to insert a strict pre-03 integrity step
- Renumber existing scripts explicitly: **`03`-`13` become `04`-`14`**.
- Introduce a new `03` operator script (for example, `03_prepare_supply_chain_integrity.sh`) so sequence stays strict and monotonic.
- Scope of new pre-03 script:
  - compile/refresh pip-tools lockfiles with hashes
  - generate/update SBOM baseline artifacts and signing/attestation inputs (or deterministic placeholders when signing context is unavailable)
  - fail fast on lock/SBOM generation errors before install proceeds
- Update numbered-script references so the scheme is perfectly consistent across:
  - operator script names and wrappers
  - tests and fixtures that call numbered scripts
  - requirements traceability docs and filename references
  - README and other workflow docs

### 1) Introduce pip-tools managed lock inputs + hashed lock outputs
- Add source requirement files:
  - [`/Users/phil/local/src/teller/requirements.in`](/Users/phil/local/src/teller/requirements.in)
  - [`/Users/phil/local/src/teller/requirements/security/requirements-security.in`](/Users/phil/local/src/teller/requirements/security/requirements-security.in)
- Keep existing `.txt` files as compiled lock outputs with hashes:
  - [`/Users/phil/local/src/teller/requirements.txt`](/Users/phil/local/src/teller/requirements.txt)
  - [`/Users/phil/local/src/teller/requirements/security/requirements-security.txt`](/Users/phil/local/src/teller/requirements/security/requirements-security.txt)
- Add a reproducible compile command path (called by the new pre-03 script), e.g. `pip-compile --generate-hashes` for both lockfiles, with deterministic flags and headers.

### 2) Enforce hash verification at install time (03 path) and in lane-managed installs
- Keep `03` as the runtime dependency install gate (install-time integrity), but enforce hashed lock usage without editing the locked `03` script by ensuring `requirements.txt` remains a fully hashed lock output.
- Update lane-managed install commands in security scripts to require hashes explicitly:
  - [`/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh)
  - [`/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh)
  - shared helpers in [`/Users/phil/local/src/teller/src/scripts/security/common.sh`](/Users/phil/local/src/teller/src/scripts/security/common.sh) where applicable
- Add explicit failure messaging when a requirements file lacks hashes or drifts from compiled lock output.

### 3) Add SBOM generation and signing/attestation scaffold to security lane
- Add a dedicated script under `src/scripts/security/` to:
  - generate CycloneDX SBOM artifact for Python deps
  - emit signed-artifact scaffolding (cosign/sigstore-style commands and outputs) in non-destructive mode unless signing credentials/context are present
  - write outputs to `artifacts/security/reports` (e.g., `sbom.cdx.json`, `sbom.signature`, `sbom.attestation.json` or clearly named placeholders)
- Wire this script into [`/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh) so CI-facing security execution always produces the SBOM artifact and validates expected signing outputs per configured mode.
- Extend prerequisites in [`/Users/phil/local/src/teller/01_install_prerequisites.sh`](/Users/phil/local/src/teller/01_install_prerequisites.sh) for required tooling (pip-tools + SBOM/signing CLI dependencies used by the lane).

### 4) Add tests and requirement-traceability coverage
- Update shell tests that assert install command behavior:
  - [`/Users/phil/local/src/teller/tests/sh/t03_run_static_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/t03_run_static_security_tests.bats)
  - [`/Users/phil/local/src/teller/tests/sh/t12_run_dynamic_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/t12_run_dynamic_security_tests.bats)
- Add/extend tests for:
  - `--require-hashes` enforcement
  - SBOM artifact presence and basic schema sanity
  - signing scaffold behavior (expected pass/fail by mode)
- Update corresponding requirements docs under [`/Users/phil/local/src/teller/requirements/`](/Users/phil/local/src/teller/requirements/) for new/changed requirements IDs.

### 5) Documentation + operator workflow updates
- Update [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md) with:
  - renumbered strict operator sequence (new pre-03 step inserted)
  - pip-tools workflow (`*.in` -> hashed `*.txt`)
  - lock refresh command(s)
  - security lane SBOM/signing outputs and how to consume them
- Update architecture/security and requirements docs so numbering + flow references are fully consistent and auditable.

## Verification Criteria
- New pre-03 operator step runs before dependency install in strict numbered order.
- All former `03`-`13` assets are consistently shifted to `04`-`14` with no stale references.
- Requirements docs, tests, and README are mutually consistent with the new numbering scheme.
- Install-time integrity is effective in `03` by consuming hashed lockfiles.
- Hash-pinned install path is enforceable and tested in security lanes (`pip install --require-hashes -r ...`).
- Lock compilation is reproducible from `.in` files and fails fast on drift.
- Security lane emits SBOM artifact on every run.
- Signing/attestation scaffold emits expected outputs (or deterministic policy failure when required inputs are absent).
- Updated tests and traceability docs pass without regressing existing lanes.

## Constraints Handled
- No direct edits planned to locked file [`/Users/phil/local/src/teller/04_load_requirements.sh`](/Users/phil/local/src/teller/04_load_requirements.sh); install-time integrity is achieved by hashed lockfile inputs and pre-03 preparation.