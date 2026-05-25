#!/usr/bin/env python3
# Requirement test-case tags for requirements/src/scripts/mutmut_darwin-requirements.md
# #R010-T01: Verify setproctitle stub module registration behavior.

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


class MutmutDarwinStubTests(unittest.TestCase):
    def test_stub_registers_setproctitle_module(self) -> None:
        #R010
        repo_root = Path(__file__).resolve().parents[2]
        script_path = repo_root / "src" / "scripts" / "mutmut_darwin_stub.py"
        sys.modules.pop("setproctitle", None)
        spec = importlib.util.spec_from_file_location("mutmut_darwin_stub", script_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("Unable to load mutmut_darwin_stub module")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertIn("setproctitle", sys.modules)
        self.assertTrue(hasattr(sys.modules["setproctitle"], "setproctitle"))


if __name__ == "__main__":
    unittest.main()
