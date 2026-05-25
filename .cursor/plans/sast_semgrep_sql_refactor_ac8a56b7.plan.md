---
name: sast semgrep sql refactor
overview: Refactor the three Semgrep-blocking dynamic SQL paths in the classification API to SQLAlchemy expression constructs, add focused unit coverage for the matchy endpoints, and verify the SAST gate passes.
todos:
  - id: refactor-transition-update
    content: Refactor _transition_match_state to SQLAlchemy expression update without text(f"...")
    status: completed
  - id: refactor-matchy-review-selects
    content: Refactor list_matchy_review COUNT and row queries to SQLAlchemy expression selects with shared predicates
    status: completed
  - id: add-matchy-unit-tests
    content: Add/extend unit tests for match state transitions and match review filtering/pagination behavior
    status: completed
  - id: verify-sast-gate
    content: Run classification API tests and 06_run_static_security_tests.sh; confirm Semgrep blockers are eliminated
    status: completed
isProject: false
---

# Eliminate Dynamic SQL Semgrep Blockers

## What is failing now
- `./06_run_static_security_tests.sh` fails only on Semgrep high/critical findings (6 total), all in [`teller/teller_classification_api.py`](teller/teller_classification_api.py).
- The failures map to three dynamic SQL call sites using `text(f"...")`: one in `_transition_match_state` and two in `list_matchy_review` (`COUNT(*)` + row query).

## Implementation plan
- Refactor `_transition_match_state` in [`teller/teller_classification_api.py`](teller/teller_classification_api.py) from interpolated SQL text to SQLAlchemy expression API:
  - Build `UPDATE teller.transaction_email_match` via `update()`.
  - Conditionally include `email_message_id` assignment (`NULL` vs bound value) with Python-side dict/statement construction (not SQL string construction).
  - Preserve current cast semantics for enum-typed columns (`state`, `selected_by`) and returned fields used by `MatchReviewActionResponse`.
- Refactor `list_matchy_review` query construction in [`teller/teller_classification_api.py`](teller/teller_classification_api.py):
  - Replace `where_parts` string assembly with composable SQLAlchemy predicates list.
  - Build a shared filter expression (`m.active`, optional `state`, optional `only_unmoved`) and reuse it for both total and paginated queries.
  - Keep sort and pagination behavior identical (`selected_at DESC`, `match_id DESC`, `LIMIT/OFFSET`).
- Add targeted unit tests in [`tests/py/test_teller_classification_api.py`](tests/py/test_teller_classification_api.py):
  - Verify `_transition_match_state` behavior for both override/no-email branches still commits and returns expected model values.
  - Verify `/v1/matchy/review` still applies `state` and `only_unmoved` filters and preserves pagination semantics.
  - Assert generated SQL call signatures no longer rely on f-string/interpolated SQL for these paths (behavioral guard against regression).
- Keep scanner policy unchanged in [`06_run_static_security_tests.sh`](06_run_static_security_tests.sh) and [`.semgrep.yml`](.semgrep.yml); this is a code fix, not a suppression change.

## Validation steps
- Run focused unit tests for classification API module:
  - `python -m unittest tests/py/test_teller_classification_api.py`
- Re-run SAST gate:
  - `./06_run_static_security_tests.sh`
- Confirm Semgrep findings for `teller.dynamic-sql-fstring-in-text` and `python.sqlalchemy.security.audit.avoid-sqlalchemy-text` are removed from `./.security-reports/semgrep.json`.

## Notes
- The PostgreSQL freshness warning (`Could not determine PostgreSQL server version`) is non-blocking for this SAST failure and can be handled separately if you want a follow-up plan.