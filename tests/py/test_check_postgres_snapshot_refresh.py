#!/usr/bin/env python3
import importlib.util
import sys
import types
import unittest
from pathlib import Path


def load_module():
    #R020: Cover traceability for this helper/test behavior.
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "check_postgres_freshness.py"
    spec = importlib.util.spec_from_file_location("check_postgres_freshness", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load check_postgres_freshness module")
    module = importlib.util.module_from_spec(spec)
    original_requests = sys.modules.get("requests")
    sys.modules["requests"] = types.SimpleNamespace(get=None)
    try:
        spec.loader.exec_module(module)
    finally:
        if original_requests is None:
            sys.modules.pop("requests", None)
        else:
            sys.modules["requests"] = original_requests
    return module


class SnapshotRefreshWritePolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        self.module = load_module()

    def test_skip_write_when_only_generated_at_differs(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        existing = {
            "generated_at": "2026-05-12T00:00:00Z",
            "source": "postgresql.org/support/security/<major>/",
            "cves": [{"id": "CVE-TEST-1", "severity": "high", "affected": []}],
        }
        refreshed = {
            "generated_at": "2026-05-13T00:00:00Z",
            "source": "postgresql.org/support/security/<major>/",
            "cves": [{"id": "CVE-TEST-1", "severity": "high", "affected": []}],
        }

        should_write = self.module.should_write_refreshed_snapshot(existing, refreshed)
        self.assertFalse(should_write)

    def test_write_when_cve_payload_changes(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        existing = {
            "generated_at": "2026-05-12T00:00:00Z",
            "source": "postgresql.org/support/security/<major>/",
            "cves": [{"id": "CVE-TEST-1", "severity": "high", "affected": []}],
        }
        refreshed = {
            "generated_at": "2026-05-13T00:00:00Z",
            "source": "postgresql.org/support/security/<major>/",
            "cves": [{"id": "CVE-TEST-2", "severity": "high", "affected": []}],
        }

        should_write = self.module.should_write_refreshed_snapshot(existing, refreshed)
        self.assertTrue(should_write)


class SnapshotRefreshFetchHardeningTests(unittest.TestCase):
    def setUp(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        self.module = load_module()

    def test_fetch_security_page_uses_fixed_trusted_url(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        calls: list[dict[str, object]] = []

        class FakeResponse:
            def __init__(self, *, url: str) -> None:
                #R020: Cover traceability for this helper/test behavior.
                self.url = url
                self.encoding = None
                self.text = "<html>ok</html>"

            def raise_for_status(self) -> None:
                #R020: Cover traceability for this helper/test behavior.
                return None

        def fake_get(url, **kwargs):  # type: ignore[no-untyped-def]
            #R020: Cover traceability for this helper/test behavior.
            calls.append({"url": url, "kwargs": kwargs})
            return FakeResponse(url=url)

        self.module.requests.get = fake_get

        body = self.module.fetch_postgresql_security_page("15")
        self.assertEqual(body, "<html>ok</html>")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["url"], "https://www.postgresql.org/support/security/15/")
        self.assertEqual(calls[0]["kwargs"]["allow_redirects"], False)

    def test_fetch_security_page_rejects_invalid_major(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        with self.assertRaises(ValueError):
            self.module.fetch_postgresql_security_page("15/../../etc/passwd")

    def test_fetch_security_page_rejects_untrusted_response_url(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        class FakeResponse:
            def __init__(self) -> None:
                #R020: Cover traceability for this helper/test behavior.
                self.url = "http://evil.example/support/security/15/"
                self.encoding = "utf-8"
                self.text = "<html>evil</html>"

            def raise_for_status(self) -> None:
                #R020: Cover traceability for this helper/test behavior.
                return None

        def fake_get(_url, **_kwargs):  # type: ignore[no-untyped-def]
            #R020: Cover traceability for this helper/test behavior.
            return FakeResponse()

        self.module.requests.get = fake_get

        with self.assertRaises(RuntimeError):
            self.module.fetch_postgresql_security_page("15")


if __name__ == "__main__":
    unittest.main()
