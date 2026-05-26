#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "dast_cleanup.py"
    spec = importlib.util.spec_from_file_location("dast_cleanup", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load dast_cleanup module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    sqlalchemy_stub = SimpleNamespace(text=lambda value: value)
    with mock.patch.dict(sys.modules, {"sqlalchemy": sqlalchemy_stub}):
        spec.loader.exec_module(module)
    return module


class DastCleanupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_missing_baseline_is_skipped(self) -> None:
        #R010-T01
        with tempfile.TemporaryDirectory() as tmp:
            baseline = Path(tmp) / "missing.json"
            summary = Path(tmp) / "summary.json"
            argv = sys.argv
            try:
                sys.argv = ["dast_cleanup.py", str(baseline), "run-1", str(summary)]
                rc = self.module.main()
            finally:
                sys.argv = argv
            self.assertEqual(rc, 0)
            payload = json.loads(summary.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "skipped")

    def test_profile_mismatch_refuses_without_force(self) -> None:
        #R005-T01
        with tempfile.TemporaryDirectory() as tmp:
            baseline = Path(tmp) / "baseline.json"
            summary = Path(tmp) / "summary.json"
            baseline.write_text(
                json.dumps(
                    {
                        "status": "captured",
                        "profile_name": "local",
                        "baseline_max_category_id": 0,
                        "baseline_max_match_id": 0,
                        "baseline_max_match_audit_id": 0,
                    }
                ),
                encoding="utf-8",
            )
            argv = sys.argv
            env = dict(os.environ)
            try:
                os.environ.pop("DAST_CLEANUP_FORCE", None)
                sys.argv = ["dast_cleanup.py", str(baseline), "run-2", str(summary)]
                with mock.patch.dict(
                    sys.modules,
                    {
                        "teller.teller_db": mock.Mock(get_engine=lambda: None),
                        "teller.teller_db_profile": mock.Mock(resolve_profile=lambda: SimpleNamespace(name="prod")),
                    },
                ):
                    rc = self.module.main()
            finally:
                os.environ.clear()
                os.environ.update(env)
                sys.argv = argv
            self.assertEqual(rc, 1)
            payload = json.loads(summary.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "refused")

    def test_applied_status_writes_counts(self) -> None:
        #R001-T01
        class FakeResult:
            def __init__(self, rowcount=0):
                self.rowcount = rowcount

        class FakeTx:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def execute(self, *_args, **_kwargs):
                return FakeResult(1)

        class FakeEngine:
            def begin(self):
                return FakeTx()

        with tempfile.TemporaryDirectory() as tmp:
            baseline = Path(tmp) / "baseline.json"
            summary = Path(tmp) / "summary.json"
            baseline.write_text(
                json.dumps(
                    {
                        "status": "captured",
                        "profile_name": "local",
                        "baseline_max_category_id": 5,
                        "baseline_max_match_id": 5,
                        "baseline_max_match_audit_id": 5,
                        "matches": [],
                        "classifications": [],
                        "categories": [],
                    }
                ),
                encoding="utf-8",
            )
            argv = sys.argv
            try:
                sys.argv = ["dast_cleanup.py", str(baseline), "run-3", str(summary)]
                with mock.patch.dict(
                    sys.modules,
                    {
                        "teller.teller_db": mock.Mock(get_engine=lambda: FakeEngine()),
                        "teller.teller_db_profile": mock.Mock(resolve_profile=lambda: SimpleNamespace(name="local")),
                    },
                ):
                    rc = self.module.main()
            finally:
                sys.argv = argv
            self.assertEqual(rc, 0)
            payload = json.loads(summary.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "applied")
            self.assertIn("counts", payload)


if __name__ == "__main__":
    unittest.main()
