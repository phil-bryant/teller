#!/usr/bin/env python3
# Requirement test-case tags for requirements/src/scripts/mutmut_darwin-requirements.md
# #R001-T01: Verify command routing and execute-path behavior.
# #R005-T01: Verify subprocess pytest invocation and mutant metadata updates.

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
import sys
from unittest import mock


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
    def setUp(self) -> None:
        self.module = load_module()

    def test_main_routes_prepare_and_execute(self) -> None:
        #R001
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
        #R005
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            python = root / "teller-venv" / "bin" / "python3"
            calls = {}

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


if __name__ == "__main__":
    unittest.main()
