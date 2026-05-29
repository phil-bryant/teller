# Teller Classification API Module Requirements

## Scope

Applies to `src/teller/teller_classification_api.py`.

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

R040  Statement: Require authenticated token for all classifier API endpoints.
Design: Resolve classifier write token from `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN`, cache the resolved value in-process for runtime auth checks, require `X-Teller-Write-Token` for all `/v1/*` routes (read and write), compare supplied token using constant-time equality, and return 401 for missing or invalid tokens. Rotating the 1psa token requires classifier process restart to refresh the cached value.
Tests:
- R040-T01: Submit write requests without `X-Teller-Write-Token` and verify 401 response.
- R040-T02: Submit write requests with mismatched token and verify 401 response.
- R040-T03: Submit read requests without `X-Teller-Write-Token` and verify 401 response.
- R040-T04: Invoke token resolution twice in one process and verify 1psa is called only once (cache semantics).
- R040-T05: Hit each frontend-used `/v1/*` endpoint without token and verify the API returns 401 rather than silently bypassing auth.

R045  Statement: Reject malformed mutation payloads before database persistence.
Design: Category mutation fields reject explicit `null` field values, normalize by stripping control/non-printable characters before persistence, and reject all-empty normalized hierarchy writes with HTTP 409 conflict semantics in `_write_category`; OpenAPI publishes `minProperties` plus per-field printable-string guards while allowing empty strings that normalize away during write-path validation; batch classification mutations constrain `transaction_id` format/length and cap `updates` list length.
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
Design: `/v1/matchy/transactions/{transaction_id}/candidates` resolves the most recent `transaction_email_match_run` for the transaction, selects rows from `transaction_email_candidate` ordered by `score DESC, email_received_at DESC NULLS LAST, candidate_id ASC`, and merges per-id subject, sender, and preview/body_text from Mailcart's `GET /v1/messages/{id}` into the UI-facing `{subject, from, snippet}` fields; per-id Mailcart failures degrade to `mailcart_error` on the row rather than failing the whole request. The candidate set is the union of the latest run's candidates plus any active (`active = TRUE`) `transaction_email_match` email for the transaction that is not already present in that run (e.g. a manual override against a searched email): each such active email is appended as a synthetic candidate row (no `candidate_id`/score) and enriched through the same Mailcart path so the linked email always renders in the review UI; synthetic rows are skipped by the candidate metadata cache write. Returns an empty array only when there are neither latest-run candidates nor an active matched email.
Tests:
- R060-T01: Seed multiple match runs and verify only the latest run's candidates are returned, sorted by score descending; verify empty array when no runs exist; verify empty array when the latest run has no candidates.
- R060-T02: Provide Mailcart subject/from/snippet and verify they appear merged onto each candidate row.
- R060-T03: Simulate per-id Mailcart failure for one candidate and verify the row returns with `mailcart_error` populated rather than the request 502ing.
- R060-T04: Provide Mailcart in its real per-message shape (`{message_id, sender, preview, body_text}`) and verify the rows are mapped onto `{email_message_id, from, snippet}` correctly.
- R060-T05: With an active matched email absent from the latest run, verify it is included as an enriched candidate row (deduped when already present, and returned even when no run exists).

R061  Statement: Proxy the full Mailcart message body for the review UI right pane.
Design: `/v1/matchy/messages/{email_message_id}` validates the identifier as URL-safe base64 (Microsoft Graph IDs) and proxies a GET to Mailcart's `/v1/messages/{id}`, returning `{email_message_id, subject, from, to, received_at, html_body, text_body, snippet}` (mapped from Mailcart's `{message_id, sender, recipients, preview, html_body, text_body}` envelope). Mailcart 404 surfaces as classifier 404; other upstream failures surface as 502. Base URL comes from env `MAILCART_SERVICE_BASE_URL` (defaults to `https://127.0.0.1:8788`) and must use HTTPS; invalid/non-HTTPS configuration surfaces as 503. Optional bearer token from `MAILCART_SERVICE_TOKEN` is only attached when set.
Tests:
- R061-T01: Provide a fake Mailcart payload and verify body fields are proxied; verify invalid `email_message_id` returns 400.
- R061-T02: Simulate Mailcart 404 for the id and verify classifier surfaces 404.
- R061-T03: Provide Mailcart's real per-message envelope (`{message_id, sender, recipients, preview, html_body, text_body, body_text}`) and verify the mapping onto the UI-facing shape.

R070  Statement: `/v1/transactions` returns each row's active email-match summary so the unified Match & Classify UI can render classification AND match badges in a single round-trip.
Design: The transactions list/count SQL joins `teller.transaction_email_match WHERE active = TRUE` via `LEFT JOIN LATERAL`, picking the highest-confidence row (ties broken by `selected_at DESC, match_id DESC`) as the representative for the transaction, and exposes a `match` field on `TransactionRow` containing `{match_id, email_message_id, state, ai_confidence, selected_by, moved_to_matchy_at, match_count}`. `match_count` is the total number of active match rows for the transaction (>1 when matchy linked multiple emails to one charge). Two new query parameters are introduced: `match_state` (Literal over the five `transaction_email_match_state` values plus UI-only `unmatched` and `no_email`, default `""`) filters to a specific match state, and `only_unmoved_match` (bool, default `false`) excludes transactions whose representative match has already been moved to the matchy folder. `match_state=unmatched` returns transactions with no active match row or `ai_no_match_found` not yet marked by a human; `match_state=no_email` returns only human-marked `ai_no_match_found` rows. Other enum `match_state` values filter on `tem.state` equality. Transactions with no active match row pass enum state filters unchanged (i.e., `tem.match_id IS NULL` is allowed) so the UI can also classify unmatched transactions.
Tests:
- R070-T01: Stub a transaction with multiple active match rows and verify the response carries the highest-confidence representative + `match_count > 1`.
- R070-T02: Set `match_state="ai_match_confident"` and verify the SQL filters by that state while still allowing transactions with no active match row.

R072  Statement: Allow fast transaction list loads without blocking on `COUNT(*)`.
Design: `/v1/transactions` accepts `include_total` (default `true`) and `count_only` (default `false`). When `count_only=true`, only the count query runs and `items` is empty. When `include_total=false`, the list query runs first and `total` is a lower-bound estimate (`offset + row_count`, or `offset + row_count + 1` when the page is full) so clients can paint rows before an accurate total arrives. Active-match `match_count` is computed in the same lateral scan as the representative row (window count), not a per-row correlated subquery.
Tests:
- R072-T01: Call with `count_only=true` and verify one count query and empty `items`.
- R072-T02: Call with `include_total=false` and verify only the list query runs with an estimated `total`.

R075  Statement: Accept and enforce advanced transaction scalar filters used by the macOS client.
Design: `/v1/transactions` accepts optional `start_date`, `end_date`, `institution_id`, `min_amount`, and `max_amount` query parameters. Unknown-parameter validation must treat these as first-class supported keys. Count/list SQL must apply each filter when present so API behavior matches frontend query serialization contract. Invalid `start_date` / `end_date` values must return a user-facing detail string that explicitly includes the expected date format (`YYYY-MM-DD`) and identifies whether the failing field is `start_date` or `end_date`, instead of surfacing raw validation-object payloads.
Tests:
- R075-T01: Call `/v1/transactions` over HTTPS with advanced filters and verify request succeeds and filter params reach SQL execution bindings.
- R075-T02: Call `/v1/transactions` with malformed `start_date` and verify request fails with a date-format detail string that includes `YYYY-MM-DD` and `start_date`.
- R075-T03: Call `/v1/transactions` with malformed `end_date` and verify request fails with a date-format detail string that includes `YYYY-MM-DD` and `end_date`.

R062  Statement: Proxy Mailcart search for scoped candidate discovery from structured criteria fields only.
Design: `/v1/matchy/messages/search` accepts structured criteria query params (`subject`, `sender`, `body`, `start_date`, `end_date`) plus `limit` (1-100, default 25), normalizes internal whitespace for text fields, composes a Mailcart query string (`subject:... sender:... body:... from:... to:...`), and proxies to Mailcart `/v1/messages/search?query=...&limit=...`. Scoped filters are combined with AND in composed-query order, and `from`/`to` boundaries are inclusive as date filters. The legacy `query` parameter is unsupported and must be rejected as an unknown query parameter (400). Response remains `{query, items: [{email_message_id, subject, from, received_at, snippet}]}` mapped from Mailcart's `{messages: [{message_id, sender, preview, received_at, body_text}]}` envelope. Requests with no structured criteria return 422. Upstream payloads missing a `messages` array (or legacy `items` array) surface as 502. The static `/search` route must be registered before `/v1/matchy/messages/{email_message_id}` so Starlette does not treat the literal path segment `search` as a message id (which would return an `EmailMessage` shape and break macOS client decoding). Case-insensitive and spacing-variant text matching semantics are provided by Mailcart for each scoped field.
Tests:
- R062-T01: Provide a fake Mailcart payload and verify each hit is proxied to the response; verify a malformed upstream response surfaces 502.
- R062-T02: Provide Mailcart's real `{messages: [...]}` envelope and verify each hit is mapped to the UI-facing `{email_message_id, from, snippet}` shape.
- R062-T03: Resolve `/v1/matchy/messages/search` through the app router and verify it matches the search route (not `/{email_message_id}`) and that route registration order keeps `/search` ahead of `/{email_message_id}`.
- R062-T04: Simulate a Mailcart throttling error wrapped as `MailcartError(status_code=502, message contains upstream 429)` and verify the search route preserves the 502 response contract.
- R062-T05: Call search with structured criteria and no `query`, then verify the classifier composes and forwards a Mailcart-compatible query string.
- R062-T06: Call search with legacy `query` parameter and verify request validation fails with 400 unknown-parameter error.
- R062-T07: Call search with no structured criteria and verify request validation fails with 422.
- R062-T08: Call search with date-only criteria (`end_date` or `start_date`) over HTTPS and verify response is 200 with composed query summary.
- R062-T09: Call search with structured criteria containing repeated whitespace and verify the forwarded composed query collapses internal whitespace while preserving scoped AND composition.

R071  Statement: Clear a human-reviewed match and return the transaction to unmatched.
Design: Match-review mutation endpoints include `/v1/matchy/matches/{match_id}/clear` and `/v1/matchy/transactions/{transaction_id}/clear`. Each deactivates the transaction's active `transaction_email_match` row (`active = FALSE`), records an audit row, and returns `MatchReviewActionResponse`. After clear, `/v1/transactions` no longer exposes a `match` field for that transaction (it qualifies for `match_state=unmatched`). Unknown `match_id` returns 404; clearing when no active match exists returns 404. OpenAPI documents `404` on both endpoints.
Tests:
- R071-T01: Seed a human-confirmed active match, call clear by `match_id`, and verify the row is deactivated and the transaction list omits match metadata.
- R071-T02: Seed a transaction with an active match but no caller-supplied `match_id`, call clear by `transaction_id`, and verify the same deactivation behavior.
- R071-T03: Call clear for an unknown `match_id` or a transaction with no active match and verify 404.

R073  Statement: Support manual unmatched override for valid email ids outside the latest candidate run.
Design: Add `/v1/matchy/transactions/{transaction_id}/override` as a transaction-level mutation that creates a `human_overrode_ai_match` row with the supplied `email_message_id`, while preserving posted-transaction existence, no-active-match conflict guards, email-id validation, and audit logging. Unlike `/override-candidate` and `/confirm-candidate`, this endpoint does not enforce latest-run candidate membership and returns 409 for the same write conflicts.
Tests:
- R073-T01: Register `/v1/matchy/transactions/{transaction_id}/override` in the app route set.
- R073-T02: Create a transaction-level override using an email id absent from latest candidates and verify match creation succeeds without calling candidate-membership guard.

R074  Statement: Confirm an existing no-email match by supplying a latest-run candidate email while preserving confirmed semantics.
Design: `PUT /v1/matchy/matches/{match_id}/confirm` accepts an optional mutation body for the no-email flow. When the current active row state is `ai_no_match_found`, confirm requires a valid `email_message_id` that belongs to the transaction's latest candidate run, then transitions that same match row to `human_confirmed_ai_match` with the supplied email and audit logging. Missing or unsupported candidate-email usage for this path is surfaced as `409` conflict semantics. For non-no-email states, confirm behavior remains body-less state confirmation.
Tests:
- R074-T01: Confirm a no-email match with a latest-run candidate email and verify response state is `human_confirmed_ai_match` and `email_message_id` is set.
- R074-T02: Confirm a no-email match without `email_message_id` and verify request fails with explicit `409` conflict detail.
- R074-T03: Confirm a no-email match with a non-candidate email and verify request fails with candidate-membership conflict detail.

R076  Statement: Representative match selection for `/v1/transactions` must prioritize human-reviewed outcomes over AI-confidence ordering.
Design: In the active-match lateral selection used by list/count SQL, rows selected by `human` rank ahead of `ai` rows even when AI rows have higher `ai_confidence`. Within human rows, most recent actions (`selected_at`, then `match_id`) remain tie-breakers. This preserves user-intent visibility for multi-email transactions while still returning `match_count`.
Tests:
- R076-T01: Seed one high-confidence AI row plus one human-reviewed row on the same transaction and verify `/v1/transactions` surfaces the human-reviewed row as representative.

## Changelog

- 2026-05-26: Added R072 (`include_total`, `count_only`) and optimized active-match lateral + `match_count` window aggregation for `/v1/transactions`.
- 2026-05-27: Clarified R040 runtime token cache semantics and explicit restart requirement after write-token rotation.
- 2026-05-27: Tightened R062 to structured-search-only input and removed legacy `query` support.
- 2026-05-27: Added R075 advanced transaction scalar filters and R062-T08 date-only HTTP contract coverage.
- 2026-05-27: Extended R075 with explicit friendly date-format validation behavior for malformed `start_date`/`end_date`.

- 2026-05-25: Expanded R040 authz boundary to all `/v1/*` endpoints (read and write) with shared token enforcement.
- 2026-04-22: Initial reverse-engineered requirements for `src/teller/teller_classification_api.py`.
- 2026-05-09: Added R040/R045 for 1psa-backed write-token auth and stricter mutation payload validation.
- 2026-05-10: Updated R030 single-write contract to path-only transaction identity and tightened R045 OpenAPI schema parity for category mutation payloads.
- 2026-05-10: Added R050 to map duplicate category hierarchy integrity violations to HTTP 409 conflict responses.
- 2026-05-15: Added R055 to require OpenAPI 404 documentation parity for match-review mutation endpoints.
- 2026-05-18: Added R060/R061/R062 for the Match Review three-pane UI: per-transaction candidate listing with Mailcart-enriched metadata, message-body proxy, and free-form Mailcart search proxy.
- 2026-05-19: Realigned R060/R061/R062 with the real Mailcart contract (`/v1/messages/search` returning `{messages: [...]}`; `/v1/messages/{id}` newly added in Mailcart R035) and switched config to the shared `MAILCART_SERVICE_BASE_URL`/`MAILCART_SERVICE_TOKEN` env vars used by matchy.
- 2026-05-19: Added R070 unified transactions endpoint extension (LEFT JOIN match info + `match_state` / `only_unmoved_match` filters) for the merged Match & Classify UI.
- 2026-05-19: Extended `match_state` with `unmatched` and `no_email` filters aligned with Match & Classify left-pane badges.
- 2026-05-19: Added R071 (clear match mutation endpoints to return transactions to unmatched).
- 2026-05-19: Extended R062 with route-registration ordering so `/v1/matchy/messages/search` is not shadowed by `/{email_message_id}`.
- 2026-05-27: Extended R062 with throttling-proxy traceability (`R062-T04`) for wrapped upstream 429 behavior.
- 2026-05-28: Added R073 for manual transaction-level override (`/v1/matchy/transactions/{transaction_id}/override`) that bypasses latest-candidate membership checks.
- 2026-05-28: Extended R060 so the candidates endpoint unions the active matched email (even when absent from the latest run) as an enriched synthetic candidate row; added R060-T05.
- 2026-05-29: Added R074 so match-id confirm can transition active no-email rows to `human_confirmed_ai_match` using a validated latest-run candidate email.
- 2026-05-29: Added R076 so `/v1/transactions` representative active-match selection prefers human-reviewed rows over AI-confidence ordering in multi-email scenarios.
