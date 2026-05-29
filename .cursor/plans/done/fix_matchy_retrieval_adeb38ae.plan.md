---
name: Fix matchy retrieval
overview: "Matching misses obvious emails because matchy sends unscoped search queries that mailcart rejects with HTTP 400, silently collapsing candidate discovery to \"the 75 newest inbox emails.\" Fix it client-side in matchy: emit scoped, unioned, date-windowed queries; stop treating 400s as a service outage; then a light evolution pass on amount tolerance, stale no-match caching, and a cross-boundary contract test."
todos:
  - id: scoped-queries
    content: "Rewrite _build_query/_build_broad_query into a scoped term extractor and rewrite _search_candidates to union tiered scoped (subject:/body:) searches with an optional from:/to: date window in matchy/service.py"
    status: completed
  - id: cooldown-fix
    content: Add _is_transient classification so only connection/timeout/5xx trip the Mailcart cooldown; 4xx surfaces as a real error
    status: completed
  - id: bust-cache
    content: Bump PROMPT_VERSION in ai_ranker.py and make prior ai_no_match_found verdicts non-cacheable in _maybe_cached_response
    status: completed
  - id: amount-tolerance
    content: Rewrite amount_hint_score in scoring_core.py to compare integer-cents and handle thousands separators
    status: completed
  - id: tests
    content: Update query-builder test, add cross-boundary contract test against mailcart's parser, add mailcart shape test, add comma/decimal amount cases
    status: completed
isProject: false
---

## Root cause (confirmed)

`matchy` emits plain-text queries (`_build_query` -> `"doordash payment doordash"`), but `mailcart`'s `/v1/messages/search` rejects any query lacking `subject:`/`body:`/`sender:`/`from:`/`to:` tokens with HTTP 400 ([matchy_mailcart_api.py:169-174](/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py)). Every real query 400s, so `_search_candidates` falls through to the empty-query branch and matches against only the 75 newest emails. Worse, each 400 trips a shared 15s "Mailcart unavailable" cooldown that starves sibling transactions in the threaded batch of any candidates.

This is an evolution job: keep the scoring + LLM ranker, fix the retrieval funnel that feeds them.

## Mailcart contract to honor (do not modify mailcart)
- Scoped tokens only; AND semantics across all tokens; per-value substring match; value runs until the next token; no OR in one request.
- Server scans the ~600 newest Graph messages, filters in-memory, truncates to `limit`.
- Implication: for OR/recall, matchy must issue several single-term scoped requests and union the results.

## 1. Rework query building + search in [matchy/service.py](/Users/phil/local/src/matchy/matchy/service.py)

Replace `_build_query`/`_build_broad_query` with a scoped term extractor and rewrite `_search_candidates` to union tiered scoped searches:

- Extract up to 3 distinct merchant terms (alpha tokens, len >= 4, non-digit) preferring `counterparty_name`, then `description`.
- For each term issue `subject:<term>` and `body:<term>` requests; union + dedupe by `message_id` (cap ~75).
- Optional precision: append a `from:<date> to:<date>` window around `txn.date` (default +/- 45 days, env-configurable) to each request.
- Tiered fallback, stop at first non-empty union: (a) terms + date window, (b) terms without window, (c) single broadest `body:<term>`, (d) existing empty-query recency fallback as last resort.

## 2. Fix the cooldown false-positive (same file)

Only trip `_mark_mailcart_temporarily_unavailable` on genuinely transient failures (connection errors, timeouts, HTTP 5xx). A 4xx (esp. 400) must surface as a real error, never a cooldown. Add an `_is_transient(exc)` helper and classify `requests` exceptions / `response.status_code`. Once queries are scoped, 400s should disappear entirely.

## 3. Force one clean re-evaluation (bust stale verdicts)

The retrieval change makes candidate-id sets differ from the old "75 recent" sets, so most caches self-invalidate. To guarantee a clean sweep, bump `PROMPT_VERSION` in [matchy/ai_ranker.py](/Users/phil/local/src/matchy/matchy/ai_ranker.py) (e.g. `"v1"` -> `"v2"`). Additionally, make a prior `ai_no_match_found` verdict non-cacheable in `_maybe_cached_response` ([matchy/service.py:192-235](/Users/phil/local/src/matchy/matchy/service.py)) so newly arrived receipts get re-tried instead of sticking as a permanent miss.

## 4. Amount tolerance in [matchy/scoring_core.py](/Users/phil/local/src/matchy/matchy/scoring_core.py)

`amount_hint_score` breaks on thousands separators (e.g. `1,234.56`). Rewrite to compare integer-cents: extract money-like numeric tokens from the email text (handling `,`/`.` grouping) and match against the transaction's cents. Keep it deterministic; exact-cents match (no fuzzy tip tolerance for now).

## 5. Tests

- Update `test_service_query_builders_normalize_and_filter_tokens` in [tests/py/test_service.py](/Users/phil/local/src/matchy/tests/py/test_service.py) for the new scoped output.
- New contract test: assert every query string `_search_candidates` emits is accepted by mailcart's parser by importing `_parse_scoped_query` from the mailcart script via `sys.path` (true cross-boundary guard). Add a complementary mailcart test asserting the new query shapes select the intended message via `_message_matches_criteria`.
- Add comma/decimal amount cases to [tests/py/test_scoring_core.py](/Users/phil/local/src/matchy/tests/py/test_scoring_core.py).

## Out of scope (noted, not doing now)
- Reworking scoring weights (sum 1.15 -> clamp 1.0); current behavior is acceptable once retrieval is fixed.
- The ~600-message Graph scan ceiling (server-side; would require mailcart changes).