# Transaction Classifier API Client Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/APIClient.swift`.

R001  Statement: Fetch categories and paginated transactions from the local classifier API.
Design: `ClassificationAPI` exposes `fetchCategories(...)` and `fetchTransactions(..., includeTotal:countOnly:)`, and `APIClient` resolves base URL from `TELLER_CLASSIFIER_API_URL` with secure localhost default (`https://127.0.0.1:8787`). Client configuration rejects non-HTTPS API base URLs. `fetchTransactions` sends `include_total` and `count_only` query parameters (classifier API R072). Default `URLSession` pins the local classifier cert from `TELLER_CLASSIFIER_TLS_CERT_FILE` (default `~/.teller/classifier-localhost-cert.pem`) for loopback HTTPS hosts.
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
Design: Shared `send(...)` methods set JSON headers, decode typed responses, and raise `APIError.requestFailed` on non-2xx responses. When the API returns a JSON error envelope, the client extracts a user-facing detail message (prefer `detail` text over raw JSON payloads). For transaction date validation failures (`start_date` / `end_date`), surfaced errors must include the expected date format `YYYY-MM-DD`.
Tests:
- R010-T01: Return a non-2xx response and verify the thrown error includes server-provided message text.
- R010-T02: Validate a second non-2xx API failure path to preserve explicit server-message propagation behavior.
- R010-T03: Return a transaction date validation error payload and verify the thrown error message is user-friendly and includes `YYYY-MM-DD` rather than raw JSON.

R040  Statement: Support category lifecycle mutations from the macOS classification UI.
Design: `ClassificationAPI` declares `createCategory(...)`, `updateCategory(...)`, and `deleteCategory(...)`; `APIClient` implements these by encoding `CategoryMutationRequest` for create/update and targeting `/v1/categories` REST endpoints.
Tests:
- R040-T01: Create a category and verify POST `/v1/categories` returns the created `CategoryOption`.
- R040-T02: Update and delete a category and verify PUT/DELETE requests hit `/v1/categories/{id}` and decode typed responses.

R045  Statement: Resolve classifier write token from 1psa for API authentication.
Design: `APIClient` resolves write token from pinned trusted absolute `1psa` path candidates (`/opt/homebrew/bin/1psa`, `/usr/local/bin/1psa`) with non-group/non-world-writable permission checks, sends token as `X-Teller-Write-Token` on all requests (GET and non-GET), and emits explicit error when token resolution fails.
Tests:
- R045-T01: Trigger GET and non-GET calls and verify `X-Teller-Write-Token` header is attached.
- R045-T02: Simulate missing token and verify explicit missing-token client error.
- R045-T03: Simulate default 1psa token resolution failure and verify API calls fail with `APIError.missingWriteToken`.
- R045-T04: Simulate PATH-injected `1psa` and verify token resolution ignores PATH hijack binaries.

R050  Statement: Support clearing a human-reviewed match from the macOS Match & Classify UI.
Design: `ClassificationAPI` declares `clearMatch(matchId:)` and `clearTransactionMatch(transactionId:)`; `APIClient` issues PUT requests to `/v1/matchy/matches/{match_id}/clear` and `/v1/matchy/transactions/{transaction_id}/clear` and decodes `MatchReviewActionResponse`.
Tests:
- R050-T01: Call both clear methods and verify PUT targets the expected paths and decodes the response.

R062  Statement: Proxy email search from the Match & Classify candidates pane.
Design: `ClassificationAPI` declares `searchMessages(criteria:limit:)`; `APIClient` issues GET `/v1/matchy/messages/search` with `limit` plus optional structured criteria query parameters and decodes `{query, items: [EmailSearchHit]}`.
Tests:
- R062-T01: Call `searchMessages` and verify the request targets `/v1/matchy/messages/search` with query parameters and decodes the search envelope.

R063  Statement: Encode advanced transaction filter query parameters on transaction list fetches.
Design: `fetchTransactions` sends optional `start_date`, `end_date`, `institution_id`, `min_amount`, and `max_amount` query parameters when the corresponding `TransactionFetchOptions` fields are non-empty.
Tests:
- R063-T01: Call `fetchTransactions` with advanced filter options and verify all five parameters appear on the request URL.

R064  Statement: Encode structured email search criteria on Mailcart search requests.
Design: `searchMessages(criteria:limit:)` sends optional `subject`, `sender`, `body`, `start_date`, and `end_date` query parameters from `EmailSearchCriteria` when non-empty, in addition to `limit`. Text criteria are normalized by trimming and collapsing internal whitespace before request serialization. Fields remain strictly scoped (`subject`/`sender`/`body`) and are combined by the backend using AND semantics.
Tests:
- R064-T01: Call `searchMessages` with populated criteria and verify all structured search parameters appear on the request URL.
- R064-T02: Call `searchMessages` with extra internal whitespace in text criteria and verify serialized query values collapse to single-space tokens.

R065  Statement: Keep frontend request serialization and UI test fixtures aligned with backend contract scenarios.
Design: Contract scenario corpus in `tests/contracts/frontend_backend_contract_scenarios.json` is consumed by Swift tests to verify `APIClient` query serialization and `UITestingFixtureClassificationAPI` query-summary behavior for critical transaction and email-search flows.
Tests:
- R065-T01: Validate advanced transaction filter query serialization against corpus scenarios.
- R065-T02: Validate date-only message search serialization against corpus scenarios.
- R065-T03: Validate fixture search query summary parity against corpus expected query strings.

R066  Statement: Support unmatched transaction override against explicit email ids.
Design: `ClassificationAPI` declares `overrideTransaction(transactionId:emailMessageId:note:)`; `APIClient` issues `PUT /v1/matchy/transactions/{transaction_id}/override` with `MatchOverrideRequest` JSON body and decodes `MatchReviewActionResponse`.
Tests:
- R066-T01: Call `overrideTransaction(...)` and verify request path/body match contract and decode success response.

R067  Statement: Support match-id confirm with explicit candidate email for no-email transitions.
Design: `ClassificationAPI` supports confirm-by-match-id with an optional `email_message_id` + optional note payload so the no-email confirm path can remain confirm semantics. `APIClient` sends `PUT /v1/matchy/matches/{match_id}/confirm` with no body for ordinary confirms and with `MatchOverrideRequest` JSON when a candidate email is provided, then decodes `MatchReviewActionResponse`.
Tests:
- R067-T01: Call confirm-by-match-id without a candidate and verify `PUT /v1/matchy/matches/{match_id}/confirm` sends no JSON body.
- R067-T02: Call confirm-by-match-id with candidate email/note and verify the same endpoint sends the expected payload and decodes a confirmed-state response.

R068  Statement: Classifier API base URL must be HTTPS loopback-only.
Design: `APIClient` base URL validation allows only HTTPS URLs whose hosts resolve to loopback forms (`localhost`, `127.0.0.1`, `::1`); non-loopback hosts are rejected at initialization.
Tests:
- R068-T01: Initialize client with non-loopback HTTPS URL and verify initialization fails fast.
- R068-T02: Initialize client with loopback HTTPS URLs (`localhost`, `127.0.0.1`, `[::1]`) and verify initialization succeeds.

## Changelog

- 2026-05-30: Updated R045 to pinned trusted 1psa path policy and added R068 loopback-only API base URL validation.
- 2026-04-23: Added Swift-side requirements for `APIClient.swift` based on classifier app behavior.
- 2026-04-24: Added `R040` to document category create/update/delete API client support.
- 2026-05-09: Added `R045` for 1psa-only write-token resolution and mutation header injection.
- 2026-05-19: Added R050 (clear-match mutation client methods).
- 2026-05-19: Added R062 (email search client method for Match & Classify).
- 2026-05-23: Added `R010-T02` test traceability mapping.
- 2026-05-26: Added R020 for loopback HTTPS pinning against the local classifier TLS cert.
- 2026-05-26: Added R063 (advanced transaction filter query params) and R064 (structured email search query params); updated R062 for criteria-based search.
- 2026-05-26: Extended R001 for `include_total` / `count_only` query parameters (API R072).
- 2026-05-27: Added R045-T03 traceability for default write-token resolution failure behavior.
- 2026-05-27: Added R065 shared contract-scenario corpus conformance tests for APIClient and UI test fixture parity.
- 2026-05-27: Extended R010 with JSON detail extraction and friendly `YYYY-MM-DD` messaging for transaction date validation errors.
- 2026-05-28: Added R066 for unmatched transaction override endpoint support (`/v1/matchy/transactions/{transaction_id}/override`).
- 2026-05-29: Added R067 for match-id confirm requests that optionally include candidate email payloads for no-email confirm transitions.
