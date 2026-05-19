# Teller Classification API Module Requirements

## Scope

Applies to `teller/teller_classification_api.py`.

R001  Statement: Expose a FastAPI app factory for classification workflows.
Design: `create_app()` constructs FastAPI app metadata (`title`, `version`) and registers health/read/write endpoints.
Tests:
- R001-T01: Build app from `create_app()` and verify route registration includes `/health` and `/v1/*` resources.

R005  Statement: Build category display labels from hierarchical taxonomy fields.
Design: `_display_label` concatenates non-empty category name/code segments with ` > `, preserving order from level 1 through categorization.
Tests:
- R005-T01: Provide mixed empty/non-empty category parts and verify output label includes only populated segments in order.

R010  Statement: List all available NYS SNW categories with computed display labels.
Design: `/v1/categories` selects category taxonomy columns, sorts deterministically, and returns `CategoryOption` rows with `display_label`.
Tests:
- R010-T01: Seed category rows and verify response ordering and derived label values.

R015  Statement: Return category assignment counts for reporting.
Design: `/v1/categories/counts` aggregates classification assignments via left join so categories with zero assignments are included.
Tests:
- R015-T01: Seed categories with and without assignments and verify counts include zero-assignment categories.

R020  Statement: List posted transactions with filterable search and latest classification context.
Design: `/v1/transactions` defaults to posted transactions and supports `search`, `status`, `only_unclassified`, `limit`, and `offset`; it joins account/type/details data and latest classification via lateral subquery.
Tests:
- R020-T01: Query with default params and verify only posted rows are returned.
- R020-T02: Query with `search`, `status`, and `only_unclassified` options and verify each filter path is applied.
- R020-T03: Verify `total` reflects filtered count and item ordering is date/transaction-id descending.

R025  Statement: Validate classification writes against existing posted transactions and category IDs.
Design: `_write_one` rejects unknown/non-posted transaction IDs (404), validates category existence (404), supports unclassification by delete when category is null, and writes user-type classifications via update-or-insert.
Tests:
- R025-T01: Write classification for a known posted transaction and verify persisted category, type `user`, and returned `updated_at`.
- R025-T02: Write null category and verify existing mapping is deleted.
- R025-T03: Attempt write for unknown transaction/category and verify 404 responses.

R030  Statement: Enforce transaction ID consistency for single-write endpoint.
Design: `/v1/transactions/{transaction_id}/classification` treats the path transaction ID as the sole identifier and accepts only category mutation fields in the request body.
Tests:
- R030-T01: Submit a single-write payload containing `transaction_id` and verify request validation rejects the unexpected field.

R035  Statement: Support batch classification writes with non-empty updates.
Design: `/v1/transactions/classifications` requires at least one update and applies `_write_one` for each mutation, returning one response row per input.
Tests:
- R035-T01: Submit empty update list and verify 400 response.
- R035-T02: Submit multiple updates and verify response cardinality and per-item write results.

R040  Statement: Require authenticated write token for all mutating classification endpoints.
Design: Resolve classifier write token from `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN`, require `X-Teller-Write-Token` for category/classification mutations, and return 401 for missing or invalid tokens.
Tests:
- R040-T01: Submit write requests without `X-Teller-Write-Token` and verify 401 response.
- R040-T02: Submit write requests with mismatched token and verify 401 response.

R045  Statement: Reject malformed mutation payloads before database persistence.
Design: Category mutation fields reject explicit `null` field values, normalize by stripping control/non-printable characters before persistence, and reject all-empty normalized hierarchy writes with HTTP 409 conflict semantics in `_write_category`; OpenAPI publishes `minProperties` plus per-field/non-empty guards so empty or null-only objects are schema-invalid; batch classification mutations constrain `transaction_id` format/length and cap `updates` list length.
Tests:
- R045-T01: Submit category payload with control characters and verify normalized persistence-safe values.
- R045-T02: Submit category payload with all-empty hierarchy values and verify write path returns HTTP 409 conflict.
- R045-T03: Submit category payload with explicit `null` hierarchy field values and verify validation failure.
- R045-T04: Submit classification payload with invalid transaction ID pattern or oversized batch and verify validation failure.

R050  Statement: Surface duplicate category hierarchy writes as conflict responses.
Design: Category create/update writes translate unique-index integrity violations to HTTP 409 so contract tests can classify duplicate hierarchy payloads as conflicts.
Tests:
- R050-T01: Trigger duplicate category hierarchy writes and verify HTTP 409 response.

R055  Statement: Document match-review mutation not-found behavior in OpenAPI.
Design: Match-review mutation endpoints (`/v1/matchy/matches/{match_id}/confirm`, `/override`, `/no-email`) preserve runtime 404 behavior for unknown match IDs and publish `404` ApiError responses in operation contracts.
Tests:
- R055-T01: Inspect OpenAPI operation responses for the three endpoints and verify `404` is documented.
- R055-T02: Trigger unknown `match_id` transitions and verify runtime 404 behavior remains unchanged.

R060  Statement: List latest-run email candidates for a transaction with Mailcart-enriched metadata.
Design: `/v1/matchy/transactions/{transaction_id}/candidates` resolves the most recent `transaction_email_match_run` for the transaction, selects rows from `transaction_email_candidate` ordered by `score DESC, email_received_at DESC NULLS LAST, candidate_id ASC`, and merges per-id subject, sender, and preview/body_text from Mailcart's `GET /v1/messages/{id}` into the UI-facing `{subject, from, snippet}` fields; per-id Mailcart failures degrade to `mailcart_error` on the row rather than failing the whole request. Returns 404 when no match runs exist for the transaction.
Tests:
- R060-T01: Seed multiple match runs and verify only the latest run's candidates are returned, sorted by score descending; verify 404 when no runs exist; verify empty array when the latest run has no candidates.
- R060-T02: Provide Mailcart subject/from/snippet and verify they appear merged onto each candidate row.
- R060-T03: Simulate per-id Mailcart failure for one candidate and verify the row returns with `mailcart_error` populated rather than the request 502ing.
- R060-T04: Provide Mailcart in its real per-message shape (`{message_id, sender, preview, body_text}`) and verify the rows are mapped onto `{email_message_id, from, snippet}` correctly.

R061  Statement: Proxy the full Mailcart message body for the review UI right pane.
Design: `/v1/matchy/messages/{email_message_id}` validates the identifier as URL-safe base64 (Microsoft Graph IDs) and proxies a GET to Mailcart's `/v1/messages/{id}`, returning `{email_message_id, subject, from, to, received_at, html_body, text_body, snippet}` (mapped from Mailcart's `{message_id, sender, recipients, preview, html_body, text_body}` envelope). Mailcart 404 surfaces as classifier 404; other upstream failures surface as 502. Base URL comes from env `MAILCART_SERVICE_BASE_URL` (defaults to `http://127.0.0.1:8788`); optional bearer token from `MAILCART_SERVICE_TOKEN` is only attached when set.
Tests:
- R061-T01: Provide a fake Mailcart payload and verify body fields are proxied; verify invalid `email_message_id` returns 400.
- R061-T02: Simulate Mailcart 404 for the id and verify classifier surfaces 404.
- R061-T03: Provide Mailcart's real per-message envelope (`{message_id, sender, recipients, preview, html_body, text_body, body_text}`) and verify the mapping onto the UI-facing shape.

R062  Statement: Proxy free-form Mailcart search for ad-hoc candidate discovery.
Design: `/v1/matchy/messages/search` accepts a printable-ASCII `query` (1-200 chars) and `limit` (1-100, default 25), proxies to Mailcart `/v1/messages/search?query=...&limit=...`, and returns `{query, items: [{email_message_id, subject, from, received_at, snippet}]}` (mapped from Mailcart's `{messages: [{message_id, sender, preview, received_at, body_text}]}` envelope). Upstream payloads missing a `messages` array (or legacy `items` array) surface as 502.
Tests:
- R062-T01: Provide a fake Mailcart payload and verify each hit is proxied to the response; verify a malformed upstream response surfaces 502.
- R062-T02: Provide Mailcart's real `{messages: [...]}` envelope and verify each hit is mapped to the UI-facing `{email_message_id, from, snippet}` shape.

## Changelog

- 2026-04-22: Initial reverse-engineered requirements for `teller/teller_classification_api.py`.
- 2026-05-09: Added R040/R045 for 1psa-backed write-token auth and stricter mutation payload validation.
- 2026-05-10: Updated R030 single-write contract to path-only transaction identity and tightened R045 OpenAPI schema parity for category mutation payloads.
- 2026-05-10: Added R050 to map duplicate category hierarchy integrity violations to HTTP 409 conflict responses.
- 2026-05-15: Added R055 to require OpenAPI 404 documentation parity for match-review mutation endpoints.
- 2026-05-18: Added R060/R061/R062 for the Match Review three-pane UI: per-transaction candidate listing with Mailcart-enriched metadata, message-body proxy, and free-form Mailcart search proxy.
- 2026-05-19: Realigned R060/R061/R062 with the real Mailcart contract (`/v1/messages/search` returning `{messages: [...]}`; `/v1/messages/{id}` newly added in Mailcart R035) and switched config to the shared `MAILCART_SERVICE_BASE_URL`/`MAILCART_SERVICE_TOKEN` env vars used by matchy.
