#!/usr/bin/env python3

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


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
        #R001-T01
        self._write_token("auth_token_chase.json", "token-chase")

        creds = self.module.resolve_credentials()
        self.assertEqual(creds["token"], "token-chase")
        self.assertEqual(creds["token_source"], "chase")
        self.assertEqual(creds["warnings"], [])

    def test_ambiguous_tokens_require_institution_id(self) -> None:
        #R005-T01
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials()
        self.assertEqual(creds["token"], "")
        self.assertEqual(creds["token_source"], "")
        self.assertEqual(len(creds["warnings"]), 1)
        self.assertIn("--institution-id", creds["warnings"][0])

    def test_institution_id_selects_matching_suffix(self) -> None:
        #R001
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(institution_id="fabt")
        self.assertEqual(creds["token"], "token-fabt")
        self.assertEqual(creds["token_source"], "fabt")
        self.assertEqual(creds["warnings"], [])

    def test_run_all_tokens_returns_all_candidates(self) -> None:
        #R001-T01
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(run_all_tokens=True)
        candidates = creds["token_candidates"]
        self.assertEqual(len(candidates), 2)
        self.assertEqual(candidates[0][0], "chase")
        self.assertEqual(candidates[1][0], "fabt")
        self.assertEqual(creds["warnings"], [])

    def test_run_all_tokens_respects_institution_filter(self) -> None:
        #R001-T01
        #R005-T01
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(run_all_tokens=True, institution_id="fabt")
        candidates = creds["token_candidates"]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0][0], "fabt")

    def test_build_text_report_includes_mode_status_and_checks(self) -> None:
        #R010-T01
        report = {
            "mode": "fallback",
            "status": "warn",
            "warnings": ["token missing"],
            "checks": [{"name": "doc:accounts.md", "status": "pass", "detail": "ok"}],
        }
        text = self.module.build_text_report(report)
        self.assertIn("Mode: fallback", text)
        self.assertIn("Status: warn", text)
        self.assertIn("token missing", text)
        self.assertIn("[pass] doc:accounts.md", text)


class MainExitPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.report_dir = Path(self.temp_dir.name)

    def test_require_live_fails_when_fallback_mode_is_used(self) -> None:
        #R015-T01
        args = [
            "check_teller_api_drift.py",
            "--output-json",
            str(self.report_dir / "out.json"),
            "--output-text",
            str(self.report_dir / "out.txt"),
            "--require-live",
        ]
        with patch.object(self.module, "run_live_canary", return_value={"mode": "fallback", "status": "warn", "checks": [], "warnings": ["no creds"]}), patch.object(
            self.module,
            "run_fallback_checks",
            return_value={"status": "pass", "checks": [], "warnings": []},
        ), patch.object(os, "umask", return_value=0):
            with patch("sys.argv", args):
                exit_code = self.module.main()
        self.assertEqual(exit_code, 1)

    def test_fail_on_warn_promotes_warning_to_failure(self) -> None:
        #R015-T02
        args = [
            "check_teller_api_drift.py",
            "--output-json",
            str(self.report_dir / "warn.json"),
            "--output-text",
            str(self.report_dir / "warn.txt"),
            "--fail-on-warn",
        ]
        with patch.object(self.module, "run_live_canary", return_value={"mode": "live", "status": "warn", "checks": [], "warnings": ["token missing"]}), patch.object(
            os, "umask", return_value=0
        ):
            with patch("sys.argv", args):
                exit_code = self.module.main()
        self.assertEqual(exit_code, 1)


class FallbackSourcePathTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.repo_root = Path(self.temp_dir.name)
        self.original_cwd = Path.cwd()
        os.chdir(self.repo_root)
        self.addCleanup(lambda: os.chdir(self.original_cwd))

    def _write_fallback_docs(self) -> None:
        docs_dir = self.repo_root / "docs" / "teller-api-reference"
        docs_dir.mkdir(parents=True, exist_ok=True)
        for filename in (
            "teller-api-reference-institutions.md",
            "teller-api-reference-accounts.md",
            "teller-api-reference-identity.md",
        ):
            (docs_dir / filename).write_text("# ok\n", encoding="utf-8")

    def test_fallback_checks_use_root_fetch_script_when_present(self) -> None:
        self._write_fallback_docs()
        fetch_script = self.repo_root / "07_fetch_teller_api_data.py"
        fetch_script.write_text(
            "INSTITUTIONS='/institutions'\nACCOUNTS='/accounts'\nIDENTITY='/identity'\n",
            encoding="utf-8",
        )

        report = self.module.run_fallback_checks()
        self.assertEqual(report["status"], "pass")
        source_checks = [check for check in report["checks"] if check["name"].startswith("source:")]
        self.assertEqual(len(source_checks), 1)
        self.assertTrue(source_checks[0]["name"].endswith("07_fetch_teller_api_data.py"))
        self.assertEqual(source_checks[0]["status"], "pass")

    def test_fallback_checks_warn_when_no_known_source_files_are_present(self) -> None:
        self._write_fallback_docs()
        report = self.module.run_fallback_checks()
        self.assertEqual(report["status"], "warn")
        discovery = [check for check in report["checks"] if check["name"] == "source:discovery"]
        self.assertEqual(len(discovery), 1)
        self.assertEqual(discovery[0]["status"], "warn")


if __name__ == "__main__":
    unittest.main()
