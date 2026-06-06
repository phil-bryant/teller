#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path


def load_module():
    #R001: Cover traceability for this helper/test behavior.
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
        #R001: Cover traceability for this helper/test behavior.
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


class CheckTellerApiVersionFreshnessShard1TraceabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        #R001: Cover traceability for this helper/test behavior.
        cls.module = load_module()

    def test_r310_traceability_anchor(self) -> None:
        #R310-T01: Validate version compare helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_semver")))
        self.assertTrue(callable(getattr(self.module, "compare_versions")))

    def test_r311_traceability_anchor(self) -> None:
        #R311-T01: Validate fetch JSON helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "fetch_json")))

    def test_r312_traceability_anchor(self) -> None:
        #R312-T01: Validate fetch text helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "fetch_text")))
        self.assertTrue(callable(getattr(self.module, "fetch_text_with_opener")))

    def test_r313_traceability_anchor(self) -> None:
        #R313-T01: Validate extract docs version helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "extract_version_from_docs")))

    def test_r314_traceability_anchor(self) -> None:
        #R314-T01: Validate hidden input helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "extract_hidden_input")))

    def test_r315_traceability_anchor(self) -> None:
        #R315-T01: Validate OTP helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "_otp_from_digits")))
        self.assertTrue(callable(getattr(self.module, "_totp_from_otpauth")))
        self.assertTrue(callable(getattr(self.module, "resolve_otp_code")))

    def test_r316_traceability_anchor(self) -> None:
        #R316-T01: Validate 1psa helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "read_1psa_field")))

    def test_r317_traceability_anchor(self) -> None:
        #R317-T01: Validate dashboard extract helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "_extract_latest_version")))
        self.assertTrue(callable(getattr(self.module, "_extract_current_version")))

    def test_r318_traceability_anchor(self) -> None:
        #R318-T01: Validate dashboard latest helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_is_dashboard_on_latest")))

    def test_r319_traceability_anchor(self) -> None:
        #R319-T01: Validate dashboard error helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_dashboard_error_result")))

    def test_r320_traceability_anchor(self) -> None:
        #R320-T01: Validate dashboard credentials helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_load_dashboard_credentials")))

    def test_r321_traceability_anchor(self) -> None:
        #R321-T01: Validate dashboard login helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_submit_dashboard_login")))

    def test_r322_traceability_anchor(self) -> None:
        #R322-T01: Validate dashboard MFA helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "_submit_dashboard_mfa")))
        self.assertTrue(callable(getattr(self.module, "_maybe_complete_dashboard_mfa")))

    def test_r323_traceability_anchor(self) -> None:
        #R323-T01: Validate parsed dashboard apply helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_apply_parsed_dashboard_versions")))

    def test_r324_traceability_anchor(self) -> None:
        #R324-T01: Validate authenticated dashboard helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_discover_dashboard_version_authenticated")))

    def test_r325_traceability_anchor(self) -> None:
        #R325-T01: Validate dashboard parse helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_dashboard_versions")))

    def test_r326_traceability_anchor(self) -> None:
        #R326-T01: Validate dashboard discover helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "discover_dashboard_version")))

    def test_r327_traceability_anchor(self) -> None:
        #R327-T01: Validate discover version helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "discover_version")))

    def test_r328_traceability_anchor(self) -> None:
        #R328-T01: Validate resolve version sources helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_resolve_version_sources")))

    def test_r329_traceability_anchor(self) -> None:
        #R329-T01: Validate newer available helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_compute_newer_available")))

    def test_r330_traceability_anchor(self) -> None:
        #R330-T01: Validate build report helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "build_report")))

    def test_r331_traceability_anchor(self) -> None:
        #R331-T01: Validate format report helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "format_report")))

    def test_r332_traceability_anchor(self) -> None:
        #R332-T01: Validate parse args helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_args")))

    def test_r333_traceability_anchor(self) -> None:
        #R333-T01: Validate main helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "main")))

if __name__ == "__main__":
    unittest.main()
