# Teller Client Requirements

## Scope

Applies to `07_teller_client.py`.

R001  Statement: Configure CLI behavior and log level from runtime flags.
Design: Parse `--debug`, `--dry-run`, and `--institution_id`; configure structlog by debug flag.
Tests:
- Run with `--debug` and verify debug logger configuration path executes.

R005  Statement: Load Teller auth and TLS inputs from local teller directory.
Design: Read auth token from input or `~/.teller/auth_token.json`; use cert/key under `~/.teller`.
Tests:
- Run with no explicit token and verify token file loading path is used.

R010  Statement: Retry disconnected enrollments through local repair flow.
Design: Detect `enrollment.disconnected*`, launch connect capture flow, reload auth, and retry API call once.
Tests:
- Simulate disconnected response and verify repair flow attempts retry.

R015  Statement: Fetch full transaction history via Teller pagination.
Design: Request transaction pages with `from_id` cursor until API returns empty page.
Tests:
- Mock paginated responses and verify page loop aggregates all transactions.

R020  Statement: Build enrollment contexts from default, metadata, and suffixed token sources.
Design: Merge context sources, dedupe entries, and optionally narrow by institution.
Tests:
- Provide overlapping contexts and verify dedupe keeps one entry per key.

R025  Statement: Persist fetched Teller objects unless dry-run is enabled.
Design: In normal mode, open DB session and call persistence helper; in dry-run, print no-write message.
Tests:
- Run with `--dry-run` and verify no persistence call path is taken.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `07_teller_client.py`.
