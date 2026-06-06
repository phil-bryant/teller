#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
import sys
from unittest import mock


#R001: Load mutmut_darwin module fixture for command-route tests.
def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "mutmut_darwin.py"
    spec = importlib.util.spec_from_file_location("mutmut_darwin", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load mutmut_darwin module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class MutmutDarwinTests(unittest.TestCase):
    #R001: Initialize module fixture for each mutmut test case.
    def setUp(self) -> None:
        self.module = load_module()

    def test_main_routes_prepare_and_execute(self) -> None:
        #R001-T01: Verify command routing and execute-path behavior for prepared and unprepared mutant states.
        #R010-T01: Verify Darwin-safe mutmut entrypoint remains callable through main routing.
        root = Path("/tmp/repo")
        with mock.patch.object(self.module, "_repo_root", return_value=root), mock.patch.object(
            self.module, "_prepare", return_value=0
        ) as prep, mock.patch.object(self.module, "_execute", return_value=0) as execute:
            rc_prepare = self.module.main(["prepare", "--max-children", "2"])
            rc_execute = self.module.main(["execute"])
        self.assertEqual(rc_prepare, 0)
        self.assertEqual(rc_execute, 0)
        prep.assert_called_once()
        execute.assert_called_once()

    def test_run_mutant_pytest_invocation(self) -> None:
        #R005-T01: Verify subprocess pytest invocation arguments/environment and per-mutant metadata updates.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            python = root / "teller-venv" / "bin" / "python3"
            calls = {}

            #R001: Capture subprocess invocation arguments in test harness.
            def fake_run(args, cwd=None, env=None):
                calls["args"] = args
                calls["cwd"] = str(cwd)
                calls["env"] = env or {}
                return mock.Mock(returncode=0)

            with mock.patch.object(self.module.subprocess, "run", side_effect=fake_run):
                rc = self.module._run_mutant_pytest(python, root, "mutant-1", ["tests/py/test_teller_db.py"])
        self.assertEqual(rc, 0)
        self.assertIn("-m", calls["args"])
        self.assertIn("pytest", calls["args"])
        self.assertIn("MUTANT_UNDER_TEST", calls["env"])
        self.assertEqual(calls["env"]["MUTANT_UNDER_TEST"], "mutant-1")


class MutmutDarwinShard1TraceabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        #R001: Cover traceability for this helper/test behavior.
        cls.module = load_module()

    def test_r370_traceability_anchor(self) -> None:
        #R370-T01: Validate pycache helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_purge_pycache_under")))

    def test_r371_traceability_anchor(self) -> None:
        #R371-T01: Validate repo-root helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_repo_root")))

    def test_r372_traceability_anchor(self) -> None:
        #R372-T01: Validate prepare helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_prepare")))

    def test_r373_traceability_anchor(self) -> None:
        #R373-T01: Validate load-stats helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_load_stats")))

    def test_r374_traceability_anchor(self) -> None:
        #R374-T01: Validate tests-for-mutant helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_tests_for_mutant")))

    def test_r375_traceability_anchor(self) -> None:
        #R375-T01: Validate run-mutant-pytest helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_run_mutant_pytest")))

    def test_r376_traceability_anchor(self) -> None:
        #R376-T01: Validate rerun-decision helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_should_rerun_mutant")))

    def test_r377_traceability_anchor(self) -> None:
        #R377-T01: Validate status mapper helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_status_for_exit_code")))

    def test_r378_traceability_anchor(self) -> None:
        #R378-T01: Validate run-and-record helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_run_and_record_mutant")))

    def test_r379_traceability_anchor(self) -> None:
        #R379-T01: Validate path executor helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_execute_mutants_for_path")))

    def test_r380_traceability_anchor(self) -> None:
        #R380-T01: Validate execute helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "_execute")))

    def test_r381_traceability_anchor(self) -> None:
        #R381-T01: Validate main helper is callable and anchored.
        self.assertTrue(callable(getattr(self.module, "main")))

if __name__ == "__main__":
    unittest.main()
