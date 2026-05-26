import unittest
from unittest.mock import patch

from teller.teller_mailcart_client import MailcartClient, MailcartError, get_mailcart_client, reset_mailcart_client_cache


class _FakeResponse:
    def __init__(self, status_code=200, payload=None, text=""):
        self.status_code = status_code
        self._payload = payload
        self.text = text

    def json(self):
        if self._payload is None:
            raise ValueError("invalid json")
        return self._payload


class _FakeSession:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def request(self, **kwargs):
        self.calls.append(kwargs)
        return self.response


class MailcartClientTests(unittest.TestCase):
    def test_get_message_returns_payload(self):
        session = _FakeSession(_FakeResponse(status_code=200, payload={"subject": "Receipt"}))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        payload = client.get_message("msg_1")
        self.assertEqual(payload["subject"], "Receipt")
        self.assertEqual(session.calls[0]["url"], "http://mailcart.local/v1/messages/msg_1")

    def test_search_passes_query_params(self):
        session = _FakeSession(_FakeResponse(status_code=200, payload={"messages": []}))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        payload = client.search(query="amazon", limit=5)
        self.assertEqual(payload["messages"], [])
        self.assertEqual(session.calls[0]["params"], {"query": "amazon", "limit": 5})

    def test_404_raises_not_found_error(self):
        session = _FakeSession(_FakeResponse(status_code=404, payload={"detail": "missing"}))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("unknown")
        self.assertEqual(ctx.exception.status_code, 404)

    def test_non_json_2xx_raises_bad_gateway(self):
        session = _FakeSession(_FakeResponse(status_code=200, payload=None))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("msg_1")
        self.assertEqual(ctx.exception.status_code, 502)

    def test_upstream_non_2xx_raises_bad_gateway(self):
        session = _FakeSession(_FakeResponse(status_code=500, payload={"detail": "boom"}, text="server error"))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("amazon", 5)
        self.assertEqual(ctx.exception.status_code, 502)


class MailcartClientFactoryTests(unittest.TestCase):
    def tearDown(self):
        reset_mailcart_client_cache()

    def test_factory_uses_env_and_cache(self):
        with patch.dict("os.environ", {"MAILCART_SERVICE_BASE_URL": "http://127.0.0.1:9000", "MAILCART_SERVICE_TOKEN": "abc"}):
            client_a = get_mailcart_client()
            client_b = get_mailcart_client()
        self.assertIs(client_a, client_b)
        self.assertEqual(client_a._base_url, "http://127.0.0.1:9000")
        self.assertEqual(client_a._token, "abc")


if __name__ == "__main__":
    unittest.main()
import unittest



class _FakeResponse:
    def __init__(self, status_code=200, payload=None, text=""):
        self.status_code = status_code
        self._payload = payload
        self.text = text

    def json(self):
        if self._payload is None:
            raise ValueError("invalid json")
        return self._payload


class _FakeSession:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def request(self, **kwargs):
        self.calls.append(kwargs)
        return self.response


class MailcartClientTests(unittest.TestCase):
    def test_get_message_returns_payload(self):
        session = _FakeSession(_FakeResponse(status_code=200, payload={"subject": "Receipt"}))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        payload = client.get_message("msg_1")
        self.assertEqual(payload["subject"], "Receipt")
        self.assertEqual(session.calls[0]["url"], "http://mailcart.local/v1/messages/msg_1")

    def test_search_passes_query_params(self):
        session = _FakeSession(_FakeResponse(status_code=200, payload={"messages": []}))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        payload = client.search(query="amazon", limit=5)
        self.assertEqual(payload["messages"], [])
        self.assertEqual(session.calls[0]["params"], {"query": "amazon", "limit": 5})

    def test_404_raises_not_found_error(self):
        session = _FakeSession(_FakeResponse(status_code=404, payload={"detail": "missing"}))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("unknown")
        self.assertEqual(ctx.exception.status_code, 404)

    def test_non_json_2xx_raises_bad_gateway(self):
        session = _FakeSession(_FakeResponse(status_code=200, payload=None))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.get_message("msg_1")
        self.assertEqual(ctx.exception.status_code, 502)

    def test_upstream_non_2xx_raises_bad_gateway(self):
        session = _FakeSession(_FakeResponse(status_code=500, payload={"detail": "boom"}, text="server error"))
        client = MailcartClient(base_url="http://mailcart.local", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("amazon", 5)
        self.assertEqual(ctx.exception.status_code, 502)


class MailcartClientFactoryTests(unittest.TestCase):
    def tearDown(self):
        reset_mailcart_client_cache()

    def test_factory_uses_env_and_cache(self):
        with patch.dict("os.environ", {"MAILCART_SERVICE_BASE_URL": "http://127.0.0.1:9000", "MAILCART_SERVICE_TOKEN": "abc"}):
            client_a = get_mailcart_client()
            client_b = get_mailcart_client()
        self.assertIs(client_a, client_b)
        self.assertEqual(client_a._base_url, "http://127.0.0.1:9000")
        self.assertEqual(client_a._token, "abc")


if __name__ == "__main__":
    unittest.main()
import os
import unittest
from unittest.mock import MagicMock

import requests



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

    def test_request_raises_502_on_request_exception(self):
        session = MagicMock()
        session.request.side_effect = requests.RequestException("boom")
        client = MailcartClient(base_url="http://mailcart.internal", session=session)
        with self.assertRaises(MailcartError) as ctx:
            client.search("receipt", 5)
        self.assertEqual(ctx.exception.status_code, 502)
        self.assertIn("request failed", ctx.exception.message)

    def test_get_mailcart_client_uses_defaults_and_cache_reset(self):
        first = get_mailcart_client()
        second = get_mailcart_client()
        self.assertIs(first, second)
        self.assertEqual(first._base_url, "http://127.0.0.1:8788")
        reset_mailcart_client_cache()
        third = get_mailcart_client()
        self.assertIsNot(first, third)

    def test_get_mailcart_client_uses_env_and_cache(self):
        os.environ["MAILCART_SERVICE_BASE_URL"] = "http://mailcart.internal:9000"
        os.environ["MAILCART_SERVICE_TOKEN"] = "cached-token"
        first = get_mailcart_client()
        second = get_mailcart_client()
        self.assertIs(first, second)
        self.assertEqual(first._base_url, "http://mailcart.internal:9000")
        self.assertEqual(first._token, "cached-token")


if __name__ == "__main__":
    unittest.main()
