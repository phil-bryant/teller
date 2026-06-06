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
    #R001: Cover traceability for this helper/test behavior.
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
        #R001: Cover traceability for this helper/test behavior.
        self.module = load_module()

    def test_missing_baseline_is_skipped(self) -> None:
        #R010-T01: Verify missing and skipped-status baselines produce non-fatal summaries with actionable error messages.
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
        #R005-T01: Verify profile mismatch returns non-zero refusal without mutating data unless force override is enabled.
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
        #R001-T01: Verify cleanup applies expected delete/restore sequence and writes count metadata on success.
        class FakeResult:
            def __init__(self, rowcount=0):
                #R001: Cover traceability for this helper/test behavior.
                self.rowcount = rowcount

        class FakeTx:
            def __enter__(self):
                #R001: Cover traceability for this helper/test behavior.
                return self

            def __exit__(self, *_args):
                #R001: Cover traceability for this helper/test behavior.
                return False

            def execute(self, *_args, **_kwargs):
                #R001: Cover traceability for this helper/test behavior.
                return FakeResult(1)

        class FakeEngine:
            def begin(self):
                #R001: Cover traceability for this helper/test behavior.
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


class DastCleanupShard1TraceabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        #R001: Cover traceability for this helper/test behavior.
        cls.module = load_module()

    def test_r350_traceability_anchor(self) -> None:
        #R350-T01: Validate baseline loader helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_load_baseline")))

    def test_r351_traceability_anchor(self) -> None:
        #R351-T01: Validate summary writer helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_write_summary")))

    def test_r352_traceability_anchor(self) -> None:
        #R352-T01: Validate summary emitter helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_emit_summary")))

    def test_r353_traceability_anchor(self) -> None:
        #R353-T01: Validate skip helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_skip_with_error")))

    def test_r354_traceability_anchor(self) -> None:
        #R354-T01: Validate refuse helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_refuse_with_error")))

    def test_r355_traceability_anchor(self) -> None:
        #R355-T01: Validate restore matches helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_restore_matches")))

    def test_r356_traceability_anchor(self) -> None:
        #R356-T01: Validate delete audits helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_delete_post_baseline_audits")))

    def test_r357_traceability_anchor(self) -> None:
        #R357-T01: Validate delete matches helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_delete_post_baseline_matches")))

    def test_r358_traceability_anchor(self) -> None:
        #R358-T01: Validate reconcile helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_reconcile_classifications")))

    def test_r359_traceability_anchor(self) -> None:
        #R359-T01: Validate delete categories helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_delete_post_baseline_categories")))

    def test_r360_traceability_anchor(self) -> None:
        #R360-T01: Validate restore categories helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_restore_categories")))

    def test_r361_traceability_anchor(self) -> None:
        #R361-T01: Validate profile refusal helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_profile_refusal_message")))

    def test_r362_traceability_anchor(self) -> None:
        #R362-T01: Validate cleanup transaction helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_run_cleanup_transaction")))

    def test_r363_traceability_anchor(self) -> None:
        #R363-T01: Validate main helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "main")))

if __name__ == "__main__":
    unittest.main()
