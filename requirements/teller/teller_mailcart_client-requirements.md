# Teller Mailcart Client Requirements

## Scope

Applies to `src/teller/teller_mailcart_client.py`.

R600  Statement: Build the Mailcart client from defaults and allow cache reset.
Design: Build a cached client from normalized defaults and expose explicit cache reset for runtime/test isolation.
Tests:
- R600-T01: Verify default client construction and cache reset behavior (`tests/py/test_teller_mailcart_client.py`).

R605  Statement: Honor environment overrides for Mailcart base URL and token.
Design: Resolve base URL and token from environment variables and cache by normalized config.
Tests:
- R605-T01: Verify env override values are used and cached client is reused (`tests/py/test_teller_mailcart_client.py`).

R610  Statement: Reload cached client when relevant environment configuration changes.
Design: Use cache keys derived from normalized base URL and token so changed values produce a new client.
Tests:
- R610-T01: Verify changed env values produce a newly built cached client (`tests/py/test_teller_mailcart_client.py`).

R615  Statement: Reject explicit non-HTTPS base URLs.
Design: Validate configured base URL scheme and raise typed MailcartError for insecure explicit URLs.
Tests:
- R615-T01: Verify explicit `http://` base URLs are rejected (`tests/py/test_teller_mailcart_client.py`).

R620  Statement: Reject non-HTTPS base URLs sourced from environment.
Design: Validate env-derived base URL with same HTTPS requirements as explicit configuration.
Tests:
- R620-T01: Verify env-provided `http://` base URLs are rejected (`tests/py/test_teller_mailcart_client.py`).

R625  Statement: Attach bearer token header when token configuration exists.
Design: Include `Authorization: Bearer <token>` in outbound request headers when token is set.
Tests:
- R625-T01: Verify bearer token header is attached to outbound request (`tests/py/test_teller_mailcart_client.py`).

R630  Statement: Map upstream HTTP 429 responses to contextual gateway failures.
Design: Convert upstream rate-limit responses into typed 502 MailcartError with response context.
Tests:
- R630-T01: Verify upstream 429 responses map to contextual 502 errors (`tests/py/test_teller_mailcart_client.py`).

R635  Statement: Convert request transport exceptions to typed gateway failures.
Design: Catch request exceptions and raise typed 502 MailcartError.
Tests:
- R635-T01: Verify transport exceptions map to typed 502 errors (`tests/py/test_teller_mailcart_client.py`).

R640  Statement: Reject non-JSON success payloads.
Design: Parse successful responses as JSON and raise typed 502 MailcartError when decoding fails.
Tests:
- R640-T01: Verify non-JSON success payloads raise typed 502 errors (`tests/py/test_teller_mailcart_client.py`).

R645  Statement: Surface bounded upstream error response previews.
Design: Include bounded response-body preview text in typed 502 MailcartError messages.
Tests:
- R645-T01: Verify upstream error previews are surfaced in 502 context (`tests/py/test_teller_mailcart_client.py`).

R650  Statement: Map upstream 404 responses to typed not-found errors.
Design: Raise a typed 404 MailcartError when upstream message resources are missing.
Tests:
- R650-T01: Verify upstream 404 responses map to typed not-found errors (`tests/py/test_teller_mailcart_client.py`).
