# Transaction Classifier API Client Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/APIClient.swift`.

R001  Statement: Fetch categories and paginated transactions from the local classifier API.
Design: `ClassificationAPI` exposes `fetchCategories(...)` and `fetchTransactions(...)`, and `APIClient` resolves base URL from `TELLER_CLASSIFIER_API_URL` with localhost default.
Tests:
- Call both read methods and verify requests target `/v1/categories` and `/v1/transactions` with expected query parameters.

R005  Statement: Submit classification changes in batch form.
Design: `saveClassifications(...)` encodes `ClassificationBatchRequest` and posts it to `/v1/transactions/classifications`.
Tests:
- Send multiple updates and verify one batched POST payload is sent with all requested mutations.

R010  Statement: Enforce shared JSON request semantics and explicit API error propagation.
Design: Shared `send(...)` methods set JSON headers, decode typed responses, and raise `APIError.requestFailed` on non-2xx responses.
Tests:
- Return a non-2xx response and verify the thrown error includes server-provided message text.

## Changelog

- 2026-04-23: Added Swift-side requirements for `APIClient.swift` based on classifier app behavior.
