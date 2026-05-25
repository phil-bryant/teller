#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "check_teller_api_drift.py"
    spec = importlib.util.spec_from_file_location("check_teller_api_drift", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load check_teller_api_drift module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ResolveCredentialsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.teller_dir = Path(self.temp_dir.name)
        self.module.HOME_TELLER_DIR = self.teller_dir

    def _write_token(self, filename: str, token: str) -> None:
        payload = {"current": token}
        (self.teller_dir / filename).write_text(json.dumps(payload), encoding="utf-8")

    def test_suffix_only_token_is_resolved(self) -> None:
        self._write_token("auth_token_chase.json", "token-chase")

        creds = self.module.resolve_credentials()
        self.assertEqual(creds["token"], "token-chase")
        self.assertEqual(creds["token_source"], "chase")
        self.assertEqual(creds["warnings"], [])

    def test_ambiguous_tokens_require_institution_id(self) -> None:
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials()
        self.assertEqual(creds["token"], "")
        self.assertEqual(creds["token_source"], "")
        self.assertEqual(len(creds["warnings"]), 1)
        self.assertIn("--institution-id", creds["warnings"][0])

    def test_institution_id_selects_matching_suffix(self) -> None:
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(institution_id="fabt")
        self.assertEqual(creds["token"], "token-fabt")
        self.assertEqual(creds["token_source"], "fabt")
        self.assertEqual(creds["warnings"], [])

    def test_run_all_tokens_returns_all_candidates(self) -> None:
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(run_all_tokens=True)
        candidates = creds["token_candidates"]
        self.assertEqual(len(candidates), 2)
        self.assertEqual(candidates[0][0], "chase")
        self.assertEqual(candidates[1][0], "fabt")
        self.assertEqual(creds["warnings"], [])

    def test_run_all_tokens_respects_institution_filter(self) -> None:
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(run_all_tokens=True, institution_id="fabt")
        candidates = creds["token_candidates"]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0][0], "fabt")


if __name__ == "__main__":
    unittest.main()
