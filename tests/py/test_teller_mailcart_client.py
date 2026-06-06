import os
import unittest
from unittest.mock import MagicMock

import requests

from teller.teller_mailcart_client import (
    MailcartClient,
    MailcartError,
    get_mailcart_client,
    reset_mailcart_client_cache,
)


class _Response:
    #R600: Build fake HTTP response object for Mailcart client tests.
    def __init__(self, status_code, payload=None, text=""):
        self.status_code = status_code
        self._payload = payload
        self.text = text

    #R600: Return fake response JSON payload or raise parse error.
    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


class MailcartClientTests(unittest.TestCase):
    #R600: Reset mailcart client cache and env before each test.
    def setUp(self):
        reset_mailcart_client_cache()
        self._saved_base = os.environ.pop("MAILCART_SERVICE_BASE_URL", None)
        self._saved_token = os.environ.pop("MAILCART_SERVICE_TOKEN", None)

    #R600: Restore mailcart client cache and env after each test.
    def tearDown(self):
        reset_mailcart_client_cache()
        os.environ.pop("MAILCART_SERVICE_BASE_URL", None)
        os.environ.pop("MAILCART_SERVICE_TOKEN", None)
        if self._saved_base is not None:
            os.environ["MAILCART_SERVICE_BASE_URL"] = self._saved_base
        if self._saved_token is not None:
            os.environ["MAILCART_SERVICE_TOKEN"] = self._saved_token

    def test_request_attaches_bearer_token_when_configured(self):
        #R625-T01: Verify bearer token header is attached to outbound requests.
        session = MagicMock()
        session.request.return_value = _Response(200, payload={"message_id": "m_1"})
        client = MailcartClient(base_url="https://mailcart.internal", token="secret-token", session=session)
        payload = client.get_message("m_1")
        self.assertEqual(payload["message_id"], "m_1")
        headers = session.request.call_args.kwargs["headers"]
        self.assertEqual(headers["Authorization"], "Bearer secret-token")
        self.assertEqual(headers["Accept"], "application/json")

    def test_request_returns_not_found_as_404_mailcart_error(self):
        #R650-T01: Verify upstream 404 maps to typed not-found MailcartError.
        session = MagicMock()
        session.request.return_value = _Response(404, text="missing")
        client = MailcartClient(base_url="https://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("missing")
        self.assertEqual(ctx.exception.status_code, 404)

    def test_request_rejects_non_json_success_payload(self):
        #R640-T01: Verify non-JSON success payload is rejected.
        session = MagicMock()
        session.request.return_value = _Response(200, payload=ValueError("bad json"))
        client = MailcartClient(base_url="https://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("not valid JSON", ctx.exception.message)

    def test_request_reports_upstream_error_preview(self):
        #R645-T01: Verify upstream error preview is surfaced in 502 context.
        session = MagicMock()
        session.request.return_value = _Response(500, payload={"error": True}, text="server exploded")
        client = MailcartClient(base_url="https://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("upstream returned 500", ctx.exception.message)

    def test_request_maps_upstream_429_to_502_with_context(self):
        #R630-T01: Verify upstream 429 maps to contextual 502 error.
        session = MagicMock()
        session.request.return_value = _Response(429, payload={"error": True}, text="slow down")
        client = MailcartClient(base_url="https://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("upstream returned 429", ctx.exception.message)
        self.assertIn("slow down", ctx.exception.message)

    def test_request_raises_502_on_request_exception(self):
        #R635-T01: Verify transport exceptions map to 502 MailcartError.
        session = MagicMock()
        session.request.side_effect = requests.RequestException("boom")
        client = MailcartClient(base_url="https://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("request failed", ctx.exception.message)

    def test_get_mailcart_client_uses_defaults_and_cache_reset(self):
        #R600-T01: Verify default client construction and cache reset behavior.
        first = get_mailcart_client()
        second = get_mailcart_client()
        self.assertIs(first, second)
        self.assertEqual(first._base_url, "https://127.0.0.1:8788")
        reset_mailcart_client_cache()
        third = get_mailcart_client()
        self.assertIsNot(first, third)

    def test_get_mailcart_client_uses_env_and_cache(self):
        #R605-T01: Verify env overrides and cached-client reuse behavior.
        os.environ["MAILCART_SERVICE_BASE_URL"] = "https://mailcart.internal:9000"
        os.environ["MAILCART_SERVICE_TOKEN"] = "cached-token"
        first = get_mailcart_client()
        second = get_mailcart_client()
        self.assertIs(first, second)
        self.assertEqual(first._base_url, "https://mailcart.internal:9000")
        self.assertEqual(first._token, "cached-token")

    def test_get_mailcart_client_reloads_when_env_changes(self):
        #R610-T01: Verify cache key changes trigger client reload on env change.
        os.environ["MAILCART_SERVICE_BASE_URL"] = "https://mailcart.internal:9000"
        os.environ["MAILCART_SERVICE_TOKEN"] = "cached-token"
        first = get_mailcart_client()

        os.environ["MAILCART_SERVICE_BASE_URL"] = "https://mailcart.internal:9001"
        os.environ["MAILCART_SERVICE_TOKEN"] = "rotated-token"
        second = get_mailcart_client()

        self.assertIsNot(first, second)
        self.assertEqual(second._base_url, "https://mailcart.internal:9001")
        self.assertEqual(second._token, "rotated-token")

    def test_rejects_http_base_url(self):
        #R615-T01: Verify explicit http base URL is rejected.
        with self.assertRaises(MailcartError) as ctx:
            MailcartClient(base_url="http://mailcart.internal")
        self.assertEqual(ctx.exception.status_code, 503)
        self.assertIn("must use https", ctx.exception.message)

    def test_rejects_http_base_url_from_env(self):
        #R620-T01: Verify env-sourced http base URL is rejected.
        os.environ["MAILCART_SERVICE_BASE_URL"] = "http://mailcart.internal:9000"
        with self.assertRaises(MailcartError) as ctx:
            get_mailcart_client()
        self.assertEqual(ctx.exception.status_code, 503)
        self.assertIn("must use https", ctx.exception.message)


if __name__ == "__main__":
    unittest.main()
