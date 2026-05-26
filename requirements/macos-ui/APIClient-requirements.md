# Transaction Classifier API Client Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/APIClient.swift`.

R001  Statement: Fetch categories and paginated transactions from the local classifier API.
Design: `ClassificationAPI` exposes `fetchCategories(...)` and `fetchTransactions(..., includeTotal:countOnly:)`, and `APIClient` resolves base URL from `TELLER_CLASSIFIER_API_URL` with secure localhost default (`https://127.0.0.1:8787`, or explicit `TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP=true` override). `fetchTransactions` sends `include_total` and `count_only` query parameters (classifier API R072). Default `URLSession` pins the local classifier cert from `TELLER_CLASSIFIER_TLS_CERT_FILE` (default `~/.teller/classifier-localhost-cert.pem`) for loopback HTTPS hosts.
Tests:
- R001-T01: Call both read methods and verify requests target `/v1/categories` and `/v1/transactions` with expected query parameters.
- R001-T03: Verify `fetchTransactions` encodes `include_total` and `count_only` on the request URL.

R020  Statement: Trust the installed local classifier TLS cert for loopback HTTPS API calls.
Design: `LocalClassifierTLS` resolves the cert path from `TELLER_CLASSIFIER_TLS_CERT_FILE` with default `~/.teller/classifier-localhost-cert.pem`, and `LocalClassifierTLSSessionDelegate` anchors server trust to that cert for loopback HTTPS hosts only.
Tests:
- R020-T01: Verify default cert path resolves to `~/.teller/classifier-localhost-cert.pem`.
- R020-T02: Verify `TELLER_CLASSIFIER_TLS_CERT_FILE` overrides the default cert path.
- R020-T03: Verify loopback host detection accepts localhost and loopback IP forms.
- R020-T04: Verify pinning applies only to loopback HTTPS URLs.
- R020-T05: Verify the installed default cert PEM loads as a `SecCertificate`.

R005  Statement: Submit classification changes in batch form.
Design: `saveClassifications(...)` encodes `ClassificationBatchRequest` and posts it to `/v1/transactions/classifications`.
Tests:
- R005-T01: Send multiple updates and verify one batched POST payload is sent with all requested mutations.

R010  Statement: Enforce shared JSON request semantics and explicit API error propagation.
Design: Shared `send(...)` methods set JSON headers, decode typed responses, and raise `APIError.requestFailed` on non-2xx responses.
Tests:
- R010-T01: Return a non-2xx response and verify the thrown error includes server-provided message text.
- R010-T02: Validate a second non-2xx API failure path to preserve explicit server-message propagation behavior.

R040  Statement: Support category lifecycle mutations from the macOS classification UI.
Design: `ClassificationAPI` declares `createCategory(...)`, `updateCategory(...)`, and `deleteCategory(...)`; `APIClient` implements these by encoding `CategoryMutationRequest` for create/update and targeting `/v1/categories` REST endpoints.
Tests:
- R040-T01: Create a category and verify POST `/v1/categories` returns the created `CategoryOption`.
- R040-T02: Update and delete a category and verify PUT/DELETE requests hit `/v1/categories/{id}` and decode typed responses.

R045  Statement: Resolve classifier write token from 1psa for API authentication.
Design: `APIClient` resolves write token using `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN`, sends it as `X-Teller-Write-Token` on all requests (GET and non-GET), and emits explicit error when token resolution fails.
Tests:
- R045-T01: Trigger GET and non-GET calls and verify `X-Teller-Write-Token` header is attached.
- R045-T02: Simulate missing token and verify explicit missing-token client error.

R050  Statement: Support clearing a human-reviewed match from the macOS Match & Classify UI.
Design: `ClassificationAPI` declares `clearMatch(matchId:)` and `clearTransactionMatch(transactionId:)`; `APIClient` issues PUT requests to `/v1/matchy/matches/{match_id}/clear` and `/v1/matchy/transactions/{transaction_id}/clear` and decodes `MatchReviewActionResponse`.
Tests:
- R050-T01: Call both clear methods and verify PUT targets the expected paths and decodes the response.

R062  Statement: Proxy email search from the Match & Classify candidates pane.
Design: `ClassificationAPI` declares `searchMessages(query:limit:)`; `APIClient` issues GET `/v1/matchy/messages/search?query=...&limit=...` and decodes `{query, items: [EmailSearchHit]}`.
Tests:
- R062-T01: Call `searchMessages` and verify the request targets `/v1/matchy/messages/search` with query parameters and decodes the search envelope.

## Changelog

- 2026-04-23: Added Swift-side requirements for `APIClient.swift` based on classifier app behavior.
- 2026-04-24: Added `R040` to document category create/update/delete API client support.
- 2026-05-09: Added `R045` for 1psa-only write-token resolution and mutation header injection.
- 2026-05-19: Added R050 (clear-match mutation client methods).
- 2026-05-19: Added R062 (email search client method for Match & Classify).
- 2026-05-23: Added `R010-T02` test traceability mapping.
- 2026-05-26: Added R020 for loopback HTTPS pinning against the local classifier TLS cert.
- 2026-05-26: Extended R001 for `include_total` / `count_only` query parameters (API R072).
