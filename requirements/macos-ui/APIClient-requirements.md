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

R040  Statement: Support category lifecycle mutations from the macOS classification UI.
Design: `ClassificationAPI` declares `createCategory(...)`, `updateCategory(...)`, and `deleteCategory(...)`; `APIClient` implements these by encoding `CategoryMutationRequest` for create/update and targeting `/v1/categories` REST endpoints.
Tests:
- Create a category and verify POST `/v1/categories` returns the created `CategoryOption`.
- Update and delete a category and verify PUT/DELETE requests hit `/v1/categories/{id}` and decode typed responses.

## Changelog

- 2026-04-23: Added Swift-side requirements for `APIClient.swift` based on classifier app behavior.
- 2026-04-24: Added `R040` to document category create/update/delete API client support.
