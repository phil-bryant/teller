---
name: Classifier Security Posture Follow-up
overview: Tighten the current classifier security posture by removing ambiguity around token handling and explicitly codifying token-rotation behavior while preserving the existing auth and transport protections.
todos:
  - id: clarify-token-constants
    content: Replace cosmetic split/join token constant constructions with explicit literals where appropriate
    status: completed
  - id: document-rotation-cache
    content: Document lru_cache token semantics and restart requirement in code/docs
    status: completed
  - id: align-tests-requirements
    content: Update tests and requirement docs to reflect explicit rotation and auth expectations
    status: completed
isProject: false
---

# Classifier Security Posture Follow-up

## Goal
Raise confidence/readability on the existing `8/10` posture without changing the core security model that is already in place.

## What Is Already Strong
- Auth boundary is enforced for `/v1/*` handlers in [`/Users/phil/local/src/teller/src/teller/teller_classification_api.py`](/Users/phil/local/src/teller/src/teller/teller_classification_api.py) via `_require_authenticated_access()` / `_require_write_access()`.
- Token verification uses constant-time compare (`hmac.compare_digest`) in [`/Users/phil/local/src/teller/src/teller/teller_classification_api.py`](/Users/phil/local/src/teller/src/teller/teller_classification_api.py).
- Launcher defaults to HTTPS and local bind, with explicit escape hatches (`TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP`, `TELLER_CLASSIFIER_ALLOW_NON_LOCAL_BIND`) in [`/Users/phil/local/src/teller/08_run_classification_api.py`](/Users/phil/local/src/teller/08_run_classification_api.py).
- Write token is sourced from 1psa (`TELLER_CLASSIFIER_WRITE_TOKEN`) with startup preflight in [`/Users/phil/local/src/teller/08_run_classification_api.py`](/Users/phil/local/src/teller/08_run_classification_api.py).

## Plan
1. **Improve scanner/readability clarity**
   - Replace cosmetic split/join token-name construction for classifier constants with explicit literals where safe and appropriate in [`/Users/phil/local/src/teller/src/teller/teller_classification_api.py`](/Users/phil/local/src/teller/src/teller/teller_classification_api.py).
   - Review nearby env/token naming patterns to avoid unnecessary obfuscation-style constructs where no security value exists.

2. **Make rotation behavior explicit in code + docs**
   - Add an explicit comment/docstring on `_configured_write_token()` cache semantics (`@lru_cache(maxsize=1)`) in [`/Users/phil/local/src/teller/src/teller/teller_classification_api.py`](/Users/phil/local/src/teller/src/teller/teller_classification_api.py).
   - Update operational docs to clearly state that rotating `TELLER_CLASSIFIER_WRITE_TOKEN` requires classifier restart (already implied in architecture runbook) in [`/Users/phil/local/src/teller/Architecture.md`](/Users/phil/local/src/teller/Architecture.md).

3. **Test and requirement alignment**
   - Extend or tighten tests to assert documented behavior around auth failures and expected rotation lifecycle in [`/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py`](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py).
   - Ensure requirements text mirrors the implementation and operational expectation in:
     - [`/Users/phil/local/src/teller/requirements/teller/teller_classification_api-requirements.md`](/Users/phil/local/src/teller/requirements/teller/teller_classification_api-requirements.md)
     - [`/Users/phil/local/src/teller/requirements/08_run_classification_api-requirements.md`](/Users/phil/local/src/teller/requirements/08_run_classification_api-requirements.md)

## Expected Outcome
- Keep existing security controls unchanged.
- Remove cosmetic anti-scanner signals that can lower reviewer confidence.
- Make token-rotation/restart semantics unambiguous for engineers, operators, and auditors.
