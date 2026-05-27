---
name: Harden fetch pagination and repair prompts
overview: Make transaction pagination loop safe against infinite cursor loops, remove interactive blocking in non-TTY contexts, and replace fragile suffix slicing with explicit parsing; update unit tests to cover each safeguard.
todos:
  - id: guard-pagination-loop
    content: Add max-pages and seen-last-id guards to `_fetch_all_transactions` with clear TellerAPIError messages.
    status: completed
  - id: noninteractive-repair-failfast
    content: Refactor `_repair_enrollment` to avoid blocking input in non-TTY runs and fail fast with actionable error text.
    status: completed
  - id: replace-magic-suffix-slice
    content: Replace `[11:-5]` suffix extraction with explicit robust filename parsing and malformed-name handling.
    status: completed
  - id: expand-regression-tests
    content: Update `tests/py/test_06_fetch_teller_api_data.py` for pagination guard, non-interactive repair, and suffix parsing coverage.
    status: completed
isProject: false
---

# Harden pagination, repair prompt, and suffix parsing

## Scope
- Update transaction ingestion and enrollment-context discovery in [`/Users/phil/local/src/teller/06_fetch_teller_api_data.py`](/Users/phil/local/src/teller/06_fetch_teller_api_data.py).
- Extend regression coverage in [`/Users/phil/local/src/teller/tests/py/test_06_fetch_teller_api_data.py`](/Users/phil/local/src/teller/tests/py/test_06_fetch_teller_api_data.py).

## Planned changes
- Add defensive pagination guards in `_fetch_all_transactions`:
  - Track `seen_last_id` values to break and raise a clear `TellerAPIError` if the API repeats the same cursor (prevents infinite loops).
  - Add a configurable `max_pages` limit (constant default, optionally env-overridable) and raise a clear `TellerAPIError` if exceeded.
  - Keep existing successful pagination behavior intact for normal finite sequences.
- Remove non-interactive blocking from `_repair_enrollment`:
  - Gate the `input()` pause behind an interactive TTY check (`sys.stdin.isatty()` / `sys.stdout.isatty()`).
  - For non-interactive runs, fail fast with an actionable `TellerAPIError` describing that manual reconnect is required and should be run via the macOS UI flow.
  - Preserve current interactive repair flow for local operator-driven runs.
- Replace magic-number suffix extraction in `_load_suffix_contexts`:
  - Parse token filename suffix using explicit prefix/suffix removal (e.g., stem + `removeprefix("auth_token_")`) instead of `[11:-5]`.
  - Ignore malformed filenames safely and log at info/warn level rather than creating bad context rows.

## Test plan updates
- Add/adjust tests to verify:
  - Pagination aborts on repeated `from_id` cursor and on max-page overflow with explicit error signaling.
  - Non-interactive repair path does not call `input()` and raises fail-fast actionable error.
  - Interactive repair path still prompts and retries once.
  - Suffix-context discovery correctly parses valid `auth_token_<suffix>.json` names and ignores malformed variants.
- Keep existing R015/R020 behavior assertions passing for normal paths.

## Validation
- Run `tests/py/test_06_fetch_teller_api_data.py` focused suite first.
- If needed, run broader related Python tests for ingestion-client stability.