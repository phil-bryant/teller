# Teller Reclassification API Module Requirements

## Scope

Applies to `teller/teller_reclassification_api.py`.

R001  Statement: Expose a FastAPI app factory for reclassification workflows.
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
Design: `/v1/transactions/{transaction_id}/classification` requires path transaction ID to match payload transaction ID and returns 400 on mismatch.
Tests:
- Submit mismatched IDs and verify 400 response detail.

R035  Statement: Support batch classification writes with non-empty updates.
Design: `/v1/transactions/classifications` requires at least one update and applies `_write_one` for each mutation, returning one response row per input.
Tests:
- Submit empty update list and verify 400 response.
- Submit multiple updates and verify response cardinality and per-item write results.

## Changelog

- 2026-04-22: Initial reverse-engineered requirements for `teller/teller_reclassification_api.py`.
