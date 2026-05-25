#!/usr/bin/env python3
# Requirement test-case tags for requirements/src/scripts/dast_baseline-requirements.md
# #R001-T01: Verify baseline payload structure helpers for serialized snapshot rows.
# #R005-T01: Verify db import failure path writes a skipped payload.
# #R010-T01: Verify success-summary JSON includes expected top-level keys.

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "dast_baseline.py"
    spec = importlib.util.spec_from_file_location("dast_baseline", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load dast_baseline module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DastBaselineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_helpers_serialize_row_payload(self) -> None:
        #R001
        row = [7, datetime(2026, 1, 1, tzinfo=timezone.utc), "x"]
        serialized = self.module._serialize_row(row, ["id", "ts", "value"])
        self.assertEqual(serialized["id"], 7)
        self.assertTrue(serialized["ts"].startswith("2026-01-01T00:00:00"))
        self.assertEqual(serialized["value"], "x")

    def test_import_failure_writes_skipped_payload(self) -> None:
        #R005
        with tempfile.TemporaryDirectory() as tmp:
            output_path = Path(tmp) / "baseline.json"
            argv = sys.argv
            try:
                sys.argv = ["dast_baseline.py", str(output_path)]
                with mock.patch.dict(sys.modules, {"teller.teller_db": None, "teller.teller_db_profile": None}):
                    rc = self.module.main()
            finally:
                sys.argv = argv
            self.assertEqual(rc, 0)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "skipped")
            self.assertIn("db_import_failed", payload["reason"])

    def test_success_print_summary_shape(self) -> None:
        #R010
        class FakeProfile:
            name = "local"
            host = "localhost"
            dbname = "prod"

        class FakeConn:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def exec_driver_sql(self, sql):
                class Result:
                    def __init__(self, value):
                        self._value = value

                    def scalar_one(self):
                        return self._value

                    def fetchall(self):
                        return []

                if "MAX(nys_snw_category_id)" in sql:
                    return Result(3)
                if "MAX(match_id)" in sql:
                    return Result(4)
                if "MAX(match_audit_id)" in sql:
                    return Result(5)
                return Result(0)

        class FakeEngine:
            def connect(self):
                return FakeConn()

        with tempfile.TemporaryDirectory() as tmp:
            output_path = Path(tmp) / "baseline.json"
            argv = sys.argv
            try:
                sys.argv = ["dast_baseline.py", str(output_path)]
                with mock.patch.dict(
                    sys.modules,
                    {
                        "teller.teller_db": mock.Mock(get_engine=lambda: FakeEngine()),
                        "teller.teller_db_profile": mock.Mock(resolve_profile=lambda: FakeProfile()),
                    },
                ):
                    rc = self.module.main()
            finally:
                sys.argv = argv
            self.assertEqual(rc, 0)
            payload = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "captured")
            self.assertIn("baseline_max_category_id", payload)


if __name__ == "__main__":
    unittest.main()
