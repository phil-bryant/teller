# Teller Classification API Module Requirements

## Scope

Applies to `teller/teller_classification_api.py`.

R001  Statement: Expose a FastAPI app factory for classification workflows.
Design: `create_app()` constructs FastAPI app metadata (`title`, `version`) and registers health/read/write endpoints.
Tests:
- Build app from `create_app()` and verify route registration includes `/health` and `/v1/*` resources.

R005  Statement: Build category display labels from hierarchical taxonomy fields.
Design: `_display_label` concatenates non-empty category name/code segments with ` > `, preserving order from level 1 through categorization.
Tests:
- Provide mixed empty/non-empty category parts and verify output label includes only populated segments in order.

R010  Statement: List all available NYS SNW categories with computed display labels.
Design: `/v1/categories` selects category taxonomy columns, sorts deterministically, and returns `CategoryOption` rows with `display_label`.
Tests:
- Seed category rows and verify response ordering and derived label values.

R015  Statement: Return category assignment counts for reporting.
Design: `/v1/categories/counts` aggregates classification assignments via left join so categories with zero assignments are included.
Tests:
- Seed categories with and without assignments and verify counts include zero-assignment categories.

R020  Statement: List posted transactions with filterable search and latest classification context.
Design: `/v1/transactions` defaults to posted transactions and supports `search`, `status`, `only_unclassified`, `limit`, and `offset`; it joins account/type/details data and latest classification via lateral subquery.
Tests:
- Query with default params and verify only posted rows are returned.
- Query with `search`, `status`, and `only_unclassified` options and verify each filter path is applied.
- Verify `total` reflects filtered count and item ordering is date/transaction-id descending.

R025  Statement: Validate classification writes against existing posted transactions and category IDs.
Design: `_write_one` rejects unknown/non-posted transaction IDs (404), validates category existence (404), supports unclassification by delete when category is null, and writes user-type classifications via update-or-insert.
Tests:
- Write classification for a known posted transaction and verify persisted category, type `user`, and returned `updated_at`.
- Write null category and verify existing mapping is deleted.
- Attempt write for unknown transaction/category and verify 404 responses.

R030  Statement: Enforce transaction ID consistency for single-write endpoint.
Design: `/v1/transactions/{transaction_id}/classification` treats the path transaction ID as the sole identifier and accepts only category mutation fields in the request body.
Tests:
- Submit a single-write payload containing `transaction_id` and verify request validation rejects the unexpected field.

R035  Statement: Support batch classification writes with non-empty updates.
Design: `/v1/transactions/classifications` requires at least one update and applies `_write_one` for each mutation, returning one response row per input.
Tests:
- Submit empty update list and verify 400 response.
- Submit multiple updates and verify response cardinality and per-item write results.

R040  Statement: Require authenticated write token for all mutating classification endpoints.
Design: Resolve classifier write token from `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN`, require `X-Teller-Write-Token` for category/classification mutations, and return 401 for missing or invalid tokens.
Tests:
- Submit write requests without `X-Teller-Write-Token` and verify 401 response.
- Submit write requests with mismatched token and verify 401 response.

R045  Statement: Reject malformed mutation payloads before database persistence.
Design: Category mutation fields reject explicit `null` field values, normalize by stripping control/non-printable characters before persistence, and reject all-empty normalized hierarchy writes with HTTP 409 conflict semantics in `_write_category`; OpenAPI publishes `minProperties` plus per-field/non-empty guards so empty or null-only objects are schema-invalid; batch classification mutations constrain `transaction_id` format/length and cap `updates` list length.
Tests:
- Submit category payload with control characters and verify normalized persistence-safe values.
- Submit category payload with all-empty hierarchy values and verify write path returns HTTP 409 conflict.
- Submit category payload with explicit `null` hierarchy field values and verify validation failure.
- Submit classification payload with invalid transaction ID pattern or oversized batch and verify validation failure.

R050  Statement: Surface duplicate category hierarchy writes as conflict responses.
Design: Category create/update writes translate unique-index integrity violations to HTTP 409 so contract tests can classify duplicate hierarchy payloads as conflicts.
Tests:
- Trigger duplicate category hierarchy writes and verify HTTP 409 response.

R055  Statement: Document match-review mutation not-found behavior in OpenAPI.
Design: Match-review mutation endpoints (`/v1/matchy/matches/{match_id}/confirm`, `/override`, `/no-email`) preserve runtime 404 behavior for unknown match IDs and publish `404` ApiError responses in operation contracts.
Tests:
- Inspect OpenAPI operation responses for the three endpoints and verify `404` is documented.
- Trigger unknown `match_id` transitions and verify runtime 404 behavior remains unchanged.

## Changelog

- 2026-04-22: Initial reverse-engineered requirements for `teller/teller_classification_api.py`.
- 2026-05-09: Added R040/R045 for 1psa-backed write-token auth and stricter mutation payload validation.
- 2026-05-10: Updated R030 single-write contract to path-only transaction identity and tightened R045 OpenAPI schema parity for category mutation payloads.
- 2026-05-10: Added R050 to map duplicate category hierarchy integrity violations to HTTP 409 conflict responses.
- 2026-05-15: Added R055 to require OpenAPI 404 documentation parity for match-review mutation endpoints.
