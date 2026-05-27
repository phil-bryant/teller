---
name: Pin Security Tools And Author Metadata
overview: Pin security tooling dependencies for deterministic installs and replace placeholder project author metadata with the selected real identity.
todos:
  - id: capture-security-versions
    content: Capture currently resolved versions for the six security tools in the repo environment
    status: completed
  - id: pin-requirements-security
    content: Replace non-deterministic security dependency specs with exact == pins in requirements/security/requirements-security.txt
    status: completed
  - id: update-project-authors
    content: Replace placeholder pyproject author entry with phil-bryant + outlook email
    status: completed
  - id: validate-targeted-changes
    content: Verify pins and metadata are correct and no placeholders/unpinned targets remain
    status: completed
isProject: false
---

# Pin Security Tooling And Author Metadata

## Scope
- Update security dependency pins in [`/Users/phil/local/src/teller/requirements/security/requirements-security.txt`](/Users/phil/local/src/teller/requirements/security/requirements-security.txt).
- Replace placeholder author metadata in [`/Users/phil/local/src/teller/pyproject.toml`](/Users/phil/local/src/teller/pyproject.toml).

## Current Gaps Confirmed
- `requirements-security.txt` currently has unpinned entries for `bandit`, `detect-secrets`, `ruff`, `schemathesis`, and `semgrep` (and non-deterministic `pip-audit<2.10`).
- `pyproject.toml` currently has placeholder metadata: `authors = [{ name = "Your Name" }]`.

## Implementation Plan
1. Resolve and capture exact currently-installed versions for security tools in the active repo environment.
2. Replace all six security-tool lines with deterministic exact pins (`==`) for:
   - `bandit`
   - `detect-secrets`
   - `pip-audit`
   - `ruff`
   - `schemathesis`
   - `semgrep`
3. Update `[project].authors` in `pyproject.toml` to:
   - `{ name = "phil-bryant", email = "phil-bryant@outlook.com" }`
4. Validate determinism and metadata correctness:
   - Confirm no targeted unpinned entries remain in `requirements-security.txt`.
   - Re-read `pyproject.toml` to confirm placeholder removal and valid TOML structure.
5. Run focused checks (if available) for packaging/metadata and security requirements consumption path, then report results and any follow-up recommendations.

## Notes
- This plan intentionally keeps changes minimal and localized to the two affected files.
- Determinism is enforced via exact version pins rather than ranges for these security tools.