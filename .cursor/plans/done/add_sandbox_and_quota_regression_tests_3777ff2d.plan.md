---
name: Add sandbox and quota regression tests
overview: Add deterministic regression tests for macOS sandbox-adjacent behavior and Teller API rate-limit/quota handling without making live calls or triggering real limits.
todos:
  - id: add-teller-429-tests
    content: Add offline 429/quota/disconnected-retry regression cases to test_06_fetch_teller_api_data.py
    status: completed
  - id: add-mailcart-throttle-tests
    content: Add Mailcart 429 mapping coverage (and optional classification endpoint assertion)
    status: completed
  - id: add-macos-regression-tests
    content: Expand Swift/macOS tests for trash path, file mode enforcement, and write-token subprocess failure seams
    status: completed
  - id: add-sandbox-lane-test
    content: Add shell/bats regression for sandbox_apply restricted Swift-lane skip behavior
    status: completed
  - id: update-traceability
    content: Update requirement docs with new Rxxx-Tyy trace links and run focused test lanes
    status: completed
isProject: false
---

# Add Regression Coverage for Sandbox and Quota Paths

## Scope
- Add test coverage only (no live Teller API pressure, no intentional real quota/rate-limit events).
- Focus on deterministic unit/integration seams that already exist.

## Why this approach
- Current coverage is partial around macOS filesystem/process behavior and sparse for Teller API failure handling.
- Existing test patterns already support safe chaos simulation via fakes/mocks in Python and temp-home/file seams in Swift.

## Planned changes

### 1) Teller API rate-limit/quota chaos tests (offline)
- Extend [`/Users/phil/local/src/teller/tests/py/test_06_fetch_teller_api_data.py`](/Users/phil/local/src/teller/tests/py/test_06_fetch_teller_api_data.py) with stateful fake `requests.get` scenarios:
  - 429 response raises `TellerAPIError` with parsed status/code/message.
  - Mid-pagination 429 in `_fetch_all_transactions` fails deterministically.
  - `enrollment.disconnected*` triggers repair+retry once, while 429 does not trigger repair.
  - Multi-enrollment isolation behavior (`R025`-style) where one context fails and others continue.
- Keep tests fully local by patching module-level `requests.get` and avoiding live scripts.

### 2) Mailcart upstream throttling mapping tests
- Extend [`/Users/phil/local/src/teller/tests/py/test_teller_mailcart_client.py`](/Users/phil/local/src/teller/tests/py/test_teller_mailcart_client.py) to explicitly cover upstream 429 mapping behavior (expected local error contract, currently 502 wrapper).
- Optionally add classification-route level assertion in [`/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py`](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py) that throttled upstream still degrades according to API contract.

### 3) macOS sandbox-adjacent regression tests
- Extend Swift tests in [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectAPIClientTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectAPIClientTests.swift):
  - Assert deleted context files are moved under `~/.Trash/teller-enrollment-removals/`.
  - Assert written enrollment artifacts enforce expected file modes (`0o400`) in addition to existing token checks.
- Add/extend tests in [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift):
  - Verify `defaultWriteToken` failure path surfaces expected error when subprocess output is empty/invalid (via seam/mocking).
- Add shell-lane regression test for sandbox-restricted Swift lane behavior in [`/Users/phil/local/src/teller/tests/sh`](/Users/phil/local/src/teller/tests/sh) by stubbing `swift` output containing `sandbox_apply: Operation not permitted` and asserting graceful skip semantics.

### 4) Requirement traceability updates
- Update requirement mappings in:
  - [`/Users/phil/local/src/teller/requirements/06_fetch_teller_api_data-requirements.md`](/Users/phil/local/src/teller/requirements/06_fetch_teller_api_data-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/macos-ui/ConnectAPIClient-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/ConnectAPIClient-requirements.md)
  - and any touched requirement docs to add/adjust `Rxxx-Tyy` trace tags for new regression cases.

## Test execution plan
- Run focused Python unit tests:
  - `python3 -m unittest tests.py.test_06_fetch_teller_api_data`
  - `python3 -m unittest tests.py.test_teller_mailcart_client`
  - `python3 -m unittest tests.py.test_teller_classification_api` (targeted subset if needed)
- Run Swift package tests for `src/macos-ui` where environment supports them.
- Run relevant bats test(s) for sandbox skip lane behavior.

## Constraints respected
- No live Teller API chaos calls.
- No rate-limit probing against production endpoints.
- All chaos scenarios simulated via local mocks/fakes and deterministic fixtures.