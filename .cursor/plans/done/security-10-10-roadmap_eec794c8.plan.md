---
name: security-10-10-roadmap
overview: Raise the repo from strong local security hygiene to a defensible 10/10 posture for local single-user usage with mandatory auth on all API and email-proxy endpoints, plus enforced CI and measurable gates.
todos:
  - id: enforce-auth-all-endpoints
    content: Require authentication/authorization for every API and Mailcart endpoint and add route-level regression tests.
    status: completed
  - id: harden-transport-defaults
    content: Make secure local transport/binding defaults mandatory and sanitize token logging paths.
    status: completed
  - id: repair-security-gates
    content: Fix Bandit target scope and strengthen ZAP/Schemathesis gating with machine-readable fail conditions.
    status: completed
  - id: add-required-ci-security
    content: Add required GitHub Actions security workflows for PR and scheduled deep scans.
    status: completed
  - id: finalize-scorecard-and-exit-gates
    content: Publish scorecard + runbook and verify consecutive clean local/CI runs before 10/10 sign-off.
    status: completed
isProject: false
---

# Reach 10/10 Security (Local Single-User, Full Auth)

## Target Definition
- Security score target means: no unauthenticated data access, no known blind spots in scanners, enforced CI gates, auditable secrets/transport defaults, and repeatable verification.
- Keep local-first ergonomics, but make secure defaults mandatory and explicit.

## Phase 1: Remove High-Risk Exposure (Blockers)
- Enforce auth on all read/write API routes in [src/teller/teller_classification_api.py](src/teller/teller_classification_api.py), including transactions, categories, and review endpoints.
- Apply the same auth model to Mailcart proxy paths in [src/teller/teller_classification_api.py](src/teller/teller_classification_api.py) and token handling in [src/teller/teller_mailcart_client.py](src/teller/teller_mailcart_client.py).
- Add a single auth middleware/dependency helper to avoid per-route drift and guarantee consistent 401/403 behavior.
- Expand tests in [tests/py/test_teller_classification_api.py](tests/py/test_teller_classification_api.py) to assert unauthorized reads fail and authorized requests succeed.

## Phase 2: Secure Transport and Runtime Defaults
- Introduce HTTPS-by-default local mode for API client/server paths in [20_run_classification_api.py](20_run_classification_api.py) and [src/teller/APIClient.swift](src/teller/APIClient.swift), with explicit opt-out only for controlled dev scenarios.
- Add strict bind protections (`127.0.0.1` only by default) and startup guardrails that fail fast on unsafe host/port combinations unless an explicit override flag is set.
- Ensure auth tokens are never logged by sanitizing headers/diagnostics in API and script outputs ([src/teller/teller_classification_api.py](src/teller/teller_classification_api.py), [22_run_dynamic_security_tests.sh](22_run_dynamic_security_tests.sh)).

## Phase 3: Close Security Tooling Blind Spots
- Fix Bandit scan scope in [06_run_static_security_tests.sh](06_run_static_security_tests.sh) to include actual Python source roots (`src/teller`, `tests/py`, scripts as appropriate).
- Strengthen DAST gating in [22_run_dynamic_security_tests.sh](22_run_dynamic_security_tests.sh): require machine-readable ZAP output parsing and fail on configured severity thresholds.
- Extend Schemathesis run mode to include negative/security-focused cases in [22_run_dynamic_security_tests.sh](22_run_dynamic_security_tests.sh), with deterministic fixtures and reproducible artifacts.

## Phase 4: Enforce in CI (Not Optional)
- Add CI workflow(s) under [.github/workflows](.github/workflows) to run minimum required security gates on PRs and main branch.
- Define a fast PR gate (SAST + secret scan + targeted tests) and a fuller scheduled/nightly gate (DAST/fuzz/dependency freshness).
- Make CI required for merge and publish clear failure triage guidance in [README.md](README.md).

## Phase 5: Supply Chain and Secrets Hardening
- Tighten dependency hygiene in [requirements.txt](requirements.txt): review unpinned/transitive risk (notably `psycopg2-binary` strategy), add rationale, and enforce lock/update policy.
- Formalize secret source-of-truth and rotation/runbook docs in [README.md](README.md) and [config](config), including local compromise response steps.
- Add pre-commit/pre-push secret scanning enforcement if not already mandatory in developer flow.

## Phase 6: Evidence, Scoring, and Exit Criteria
- Create a security scorecard section in [README.md](README.md) mapping each control to script/test evidence and pass/fail criteria.
- Add regression tests for authz, transport safety, and token-redaction behavior.
- Require two consecutive clean runs (local + CI) before declaring 10/10 achieved.

## Success Criteria (10/10 Gate)
- No unauthenticated API/mailcart data endpoints.
- CI-required security checks passing on every PR.
- SAST/DAST/fuzz/dependency scans have no high findings and no known coverage gaps.
- Secure defaults (localhost + TLS/auth expectations) are enforced, not documented only.
- Security posture is auditable through deterministic artifacts and documented runbooks.
