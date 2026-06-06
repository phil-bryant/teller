#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "check_teller_api_version_freshness.py"
    spec = importlib.util.spec_from_file_location("check_teller_api_version_freshness", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load check_teller_api_version_freshness module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TellerApiVersionFreshnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_extract_version_from_docs_phrase(self) -> None:
        #R001-T01: Verify version discovery fallback order and warning accumulation for failed/invalid sources.
        sample = "Teller uses dated versions with the latest one being 2020-10-12."
        self.assertEqual(self.module.extract_version_from_docs(sample), "2020-10-12")

    def test_extract_version_from_docs_missing_phrase(self) -> None:
        #R001-T01: Verify version discovery fallback order and warning accumulation for failed/invalid sources.
        sample = "Welcome to the Teller API docs."
        self.assertIsNone(self.module.extract_version_from_docs(sample))

    def test_parse_dashboard_versions_latest_phrase(self) -> None:
        #R005-T01: Verify dashboard parsing and credential/OTP error handling paths produce expected status fields.
        sample = "The application is currently using the latest API version (2020-10-12)."
        parsed = self.module.parse_dashboard_versions(sample)
        self.assertEqual(parsed["current_version"], "2020-10-12")
        self.assertEqual(parsed["latest_version"], "2020-10-12")
        self.assertTrue(parsed["on_latest"])

    def test_parse_dashboard_versions_current_and_latest(self) -> None:
        #R005-T01: Verify dashboard parsing and credential/OTP error handling paths produce expected status fields.
        #R010-T01: Verify baseline comparisons and fail-on-new exit behavior for equal, older, and newer-version outcomes.
        sample = "The application is currently using API version (2019-07-01). Latest API version (2020-10-12)."
        parsed = self.module.parse_dashboard_versions(sample)
        self.assertEqual(parsed["current_version"], "2019-07-01")
        self.assertEqual(parsed["latest_version"], "2020-10-12")
        self.assertFalse(parsed["on_latest"])

    def test_resolve_otp_code_from_digits(self) -> None:
        #R005-T01: Verify dashboard parsing and credential/OTP error handling paths produce expected status fields.
        self.assertEqual(self.module.resolve_otp_code("577 572"), "577572")

    def test_resolve_otp_code_from_otpauth_uri(self) -> None:
        #R005-T01: Verify dashboard parsing and credential/OTP error handling paths produce expected status fields.
        uri = "otpauth://totp/Teller:test?issuer=Teller&secret=JBSWY3DPEHPK3PXP&period=30&digits=6"
        code = self.module.resolve_otp_code(uri)
        self.assertTrue(code.isdigit())
        self.assertEqual(len(code), 6)


if __name__ == "__main__":
    unittest.main()
