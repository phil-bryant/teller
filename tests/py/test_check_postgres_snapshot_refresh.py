#!/usr/bin/env python3
import importlib.util
import sys
import types
import unittest
from pathlib import Path


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "scripts" / "check_postgres_freshness.py"
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
        self.module = load_module()

    def test_skip_write_when_only_generated_at_differs(self) -> None:
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


if __name__ == "__main__":
    unittest.main()
