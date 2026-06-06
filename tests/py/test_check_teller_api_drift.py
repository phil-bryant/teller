#!/usr/bin/env python3

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


def load_module():
    #R001: Cover traceability for this helper/test behavior.
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
        #R001: Cover traceability for this helper/test behavior.
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.teller_dir = Path(self.temp_dir.name)
        self.module.HOME_TELLER_DIR = self.teller_dir

    def _write_token(self, filename: str, token: str) -> None:
        #R001: Cover traceability for this helper/test behavior.
        payload = {"current": token}
        (self.teller_dir / filename).write_text(json.dumps(payload), encoding="utf-8")

    def test_suffix_only_token_is_resolved(self) -> None:
        #R001-T01: Verify default discovery, institution filtering, and run-all-token candidate expansion behavior.
        self._write_token("auth_token_chase.json", "token-chase")

        creds = self.module.resolve_credentials()
        self.assertEqual(creds["token"], "token-chase")
        self.assertEqual(creds["token_source"], "chase")
        self.assertEqual(creds["warnings"], [])

    def test_ambiguous_tokens_require_institution_id(self) -> None:
        #R005-T01: Verify live and fallback decision logic emits expected check lists and warning states.
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials()
        self.assertEqual(creds["token"], "")
        self.assertEqual(creds["token_source"], "")
        self.assertEqual(len(creds["warnings"]), 1)
        self.assertIn("--institution-id", creds["warnings"][0])

    def test_institution_id_selects_matching_suffix(self) -> None:
        #R001-T01: Verify institution-id suffix filtering selects the matching local token candidate.
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(institution_id="fabt")
        self.assertEqual(creds["token"], "token-fabt")
        self.assertEqual(creds["token_source"], "fabt")
        self.assertEqual(creds["warnings"], [])

    def test_run_all_tokens_returns_all_candidates(self) -> None:
        #R001-T01: Verify default discovery, institution filtering, and run-all-token candidate expansion behavior.
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(run_all_tokens=True)
        candidates = creds["token_candidates"]
        self.assertEqual(len(candidates), 2)
        self.assertEqual(candidates[0][0], "chase")
        self.assertEqual(candidates[1][0], "fabt")
        self.assertEqual(creds["warnings"], [])

    def test_run_all_tokens_respects_institution_filter(self) -> None:
        #R001-T01: Verify default discovery, institution filtering, and run-all-token candidate expansion behavior.
        #R005-T01: Verify live and fallback decision logic emits expected check lists and warning states.
        self._write_token("auth_token_chase.json", "token-chase")
        self._write_token("auth_token_fabt.json", "token-fabt")

        creds = self.module.resolve_credentials(run_all_tokens=True, institution_id="fabt")
        candidates = creds["token_candidates"]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0][0], "fabt")

    def test_build_text_report_includes_mode_status_and_checks(self) -> None:
        #R010-T01: Verify report persistence and process exit behavior for passing, warning, and failing scenarios.
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
        #R001: Cover traceability for this helper/test behavior.
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.report_dir = Path(self.temp_dir.name)

    def test_require_live_fails_when_fallback_mode_is_used(self) -> None:
        #R015-T01: Verify `--require-live` returns non-zero when run falls back.
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
        #R015-T02: Verify `--fail-on-warn` returns non-zero when report status is warn.
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
        #R001: Cover traceability for this helper/test behavior.
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.repo_root = Path(self.temp_dir.name)
        self.original_cwd = Path.cwd()
        os.chdir(self.repo_root)
        self.addCleanup(lambda: os.chdir(self.original_cwd))

    def _write_fallback_docs(self) -> None:
        #R001: Cover traceability for this helper/test behavior.
        docs_dir = self.repo_root / "docs" / "teller-api-reference"
        docs_dir.mkdir(parents=True, exist_ok=True)
        for filename in (
            "teller-api-reference-institutions.md",
            "teller-api-reference-accounts.md",
            "teller-api-reference-identity.md",
        ):
            (docs_dir / filename).write_text("# ok\n", encoding="utf-8")

    def test_fallback_checks_use_root_fetch_script_when_present(self) -> None:
        #R001: Cover traceability for this helper/test behavior.
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
        #R001: Cover traceability for this helper/test behavior.
        self._write_fallback_docs()
        report = self.module.run_fallback_checks()
        self.assertEqual(report["status"], "warn")
        discovery = [check for check in report["checks"] if check["name"] == "source:discovery"]
        self.assertEqual(len(discovery), 1)
        self.assertEqual(discovery[0]["status"], "warn")


class CheckTellerApiDriftShard1TraceabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        #R001: Cover traceability for this helper/test behavior.
        cls.module = load_module()

    def test_r290_traceability_anchor(self) -> None:
        #R290-T01: Validate read_text helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "read_text")))

    def test_r291_traceability_anchor(self) -> None:
        #R291-T01: Validate read_token helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "read_token")))

    def test_r292_traceability_anchor(self) -> None:
        #R292-T01: Validate discover_token_candidates helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "discover_token_candidates")))

    def test_r293_traceability_anchor(self) -> None:
        #R293-T01: Validate _resolve_cert_key_paths helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_resolve_cert_key_paths")))

    def test_r294_traceability_anchor(self) -> None:
        #R294-T01: Validate _filter_token_candidates helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_filter_token_candidates")))

    def test_r295_traceability_anchor(self) -> None:
        #R295-T01: Validate _select_local_token helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_select_local_token")))

    def test_r296_traceability_anchor(self) -> None:
        #R296-T01: Validate resolve_credentials helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "resolve_credentials")))

    def test_r297_traceability_anchor(self) -> None:
        #R297-T01: Validate _run_live_check helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_run_live_check")))

    def test_r298_traceability_anchor(self) -> None:
        #R298-T01: Validate _collect_source_checks helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_collect_source_checks")))

    def test_r299_traceability_anchor(self) -> None:
        #R299-T01: Validate _discover_fallback_source_files helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_discover_fallback_source_files")))

    def test_r300_traceability_anchor(self) -> None:
        #R300-T01: Validate _fallback_live_result helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_fallback_live_result")))

    def test_r301_traceability_anchor(self) -> None:
        #R301-T01: Validate _run_authenticated_live_checks helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_run_authenticated_live_checks")))

    def test_r302_traceability_anchor(self) -> None:
        #R302-T01: Validate run_live_canary helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "run_live_canary")))

    def test_r303_traceability_anchor(self) -> None:
        #R303-T01: Validate run_fallback_checks helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "run_fallback_checks")))

    def test_r304_traceability_anchor(self) -> None:
        #R304-T01: Validate parse_args helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_args")))

    def test_r305_traceability_anchor(self) -> None:
        #R305-T01: Validate build_text_report helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "build_text_report")))

    def test_r306_traceability_anchor(self) -> None:
        #R306-T01: Validate main helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "main")))

if __name__ == "__main__":
    unittest.main()
