import os
import unittest
from unittest.mock import MagicMock

from teller.teller_mailcart_client import (
    MailcartClient,
    MailcartError,
    get_mailcart_client,
    reset_mailcart_client_cache,
)


class _Response:
    def __init__(self, status_code, payload=None, text=""):
        self.status_code = status_code
        self._payload = payload
        self.text = text

    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


class MailcartClientTests(unittest.TestCase):
    def setUp(self):
        reset_mailcart_client_cache()
        self._saved_base = os.environ.pop("MAILCART_SERVICE_BASE_URL", None)
        self._saved_token = os.environ.pop("MAILCART_SERVICE_TOKEN", None)

    def tearDown(self):
        reset_mailcart_client_cache()
        os.environ.pop("MAILCART_SERVICE_BASE_URL", None)
        os.environ.pop("MAILCART_SERVICE_TOKEN", None)
        if self._saved_base is not None:
            os.environ["MAILCART_SERVICE_BASE_URL"] = self._saved_base
        if self._saved_token is not None:
            os.environ["MAILCART_SERVICE_TOKEN"] = self._saved_token

    def test_request_attaches_bearer_token_when_configured(self):
        session = MagicMock()
        session.request.return_value = _Response(200, payload={"message_id": "m_1"})
        client = MailcartClient(base_url="http://mailcart.internal", token="secret-token", session=session)
        payload = client.get_message("m_1")
        self.assertEqual(payload["message_id"], "m_1")
        headers = session.request.call_args.kwargs["headers"]
        self.assertEqual(headers["Authorization"], "Bearer secret-token")
        self.assertEqual(headers["Accept"], "application/json")

    def test_request_returns_not_found_as_404_mailcart_error(self):
        session = MagicMock()
        session.request.return_value = _Response(404, text="missing")
        client = MailcartClient(base_url="http://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("missing")
        self.assertEqual(ctx.exception.status_code, 404)

    def test_request_rejects_non_json_success_payload(self):
        session = MagicMock()
        session.request.return_value = _Response(200, payload=ValueError("bad json"))
        client = MailcartClient(base_url="http://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("not valid JSON", ctx.exception.message)

    def test_request_reports_upstream_error_preview(self):
        session = MagicMock()
        session.request.return_value = _Response(500, payload={"error": True}, text="server exploded")
        client = MailcartClient(base_url="http://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("upstream returned 500", ctx.exception.message)

    def test_get_mailcart_client_uses_defaults_and_cache_reset(self):
        first = get_mailcart_client()
        second = get_mailcart_client()
        self.assertIs(first, second)
        self.assertEqual(first._base_url, "http://127.0.0.1:8788")
        reset_mailcart_client_cache()
        third = get_mailcart_client()
        self.assertIsNot(first, third)


if __name__ == "__main__":
    unittest.main()
import os
import unittest
from unittest.mock import MagicMock

import requests

from teller.teller_mailcart_client import MailcartClient, MailcartError, get_mailcart_client, reset_mailcart_client_cache


class MailcartClientTests(unittest.TestCase):
    def test_request_adds_authorization_header_when_token_present(self):
        session = MagicMock()
        response = MagicMock()
        response.status_code = 200
        response.json.return_value = {"ok": True}
        session.request.return_value = response

        client = MailcartClient("http://localhost:8788", token="token-123", session=session)
        payload = client.get_message("msg_1")

        self.assertEqual(payload, {"ok": True})
        call = session.request.call_args
        self.assertEqual(call.kwargs["headers"]["Authorization"], "Bearer token-123")
        self.assertEqual(call.kwargs["headers"]["Accept"], "application/json")

    def test_request_raises_404_as_mailcart_error(self):
        session = MagicMock()
        response = MagicMock()
        response.status_code = 404
        response.text = "not found"
        session.request.return_value = response

        client = MailcartClient("http://localhost:8788", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("missing")
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("message not found", ctx.exception.message)

    def test_request_raises_502_on_request_exception(self):
        session = MagicMock()
        session.request.side_effect = requests.RequestException("boom")
        client = MailcartClient("http://localhost:8788", session=session)

        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("request failed", ctx.exception.message)

    def test_request_raises_502_on_invalid_json(self):
        session = MagicMock()
        response = MagicMock()
        response.status_code = 200
        response.json.side_effect = ValueError("invalid json")
        session.request.return_value = response

        client = MailcartClient("http://localhost:8788", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("msg_1")
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("valid JSON", ctx.exception.message)

    def test_get_mailcart_client_uses_env_and_cache(self):
        reset_mailcart_client_cache()
        old_base_url = os.environ.get("MAILCART_SERVICE_BASE_URL")
        old_token = os.environ.get("MAILCART_SERVICE_TOKEN")
        try:
            os.environ["MAILCART_SERVICE_BASE_URL"] = "http://mailcart.internal:9000"
            os.environ["MAILCART_SERVICE_TOKEN"] = "cached-token"
            first = get_mailcart_client()
            second = get_mailcart_client()
            self.assertIs(first, second)
            self.assertEqual(first._base_url, "http://mailcart.internal:9000")
            self.assertEqual(first._token, "cached-token")
        finally:
            reset_mailcart_client_cache()
            if old_base_url is None:
                os.environ.pop("MAILCART_SERVICE_BASE_URL", None)
            else:
                os.environ["MAILCART_SERVICE_BASE_URL"] = old_base_url
            if old_token is None:
                os.environ.pop("MAILCART_SERVICE_TOKEN", None)
            else:
                os.environ["MAILCART_SERVICE_TOKEN"] = old_token


if __name__ == "__main__":
    unittest.main()
