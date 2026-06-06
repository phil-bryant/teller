#!/usr/bin/env python3

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


def load_module():
    #R001: Cover traceability for this helper/test behavior.
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "check_dependency_freshness.py"
    spec = importlib.util.spec_from_file_location("check_dependency_freshness", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load check_dependency_freshness module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class CheckDependencyFreshnessTests(unittest.TestCase):
    def setUp(self) -> None:
        #R001: Cover traceability for this helper/test behavior.
        self.module = load_module()

    def test_parse_requirements_and_classify_update(self) -> None:
        #R001-T01: Verify requirements parsing and update classification behavior for pinned and non-pinned dependencies.
        with tempfile.TemporaryDirectory() as tmp:
            req_path = Path(tmp) / "requirements.txt"
            req_path.write_text(
                "requests==2.30.0\n"
                "urllib3>=2.1.0\n"
                "# comment\n"
                "numpy==1.26.4\n",
                encoding="utf-8",
            )
            specs = self.module.parse_requirements(req_path)
        self.assertTrue(specs["requests"].is_exact_pin)
        self.assertEqual(specs["requests"].pinned_version, "2.30.0")
        self.assertFalse(specs["urllib3"].is_exact_pin)
        self.assertEqual(self.module.classify_update("1.0.0", "2.0.0"), "major")
        self.assertEqual(self.module.classify_update("1.2.0", "1.3.0"), "minor")
        self.assertEqual(self.module.classify_update("1.2.3", "1.2.4"), "patch")

    def test_make_report_and_format_text(self) -> None:
        #R005-T01: Run the script with mocked outdated package rows and verify both report formats contain expected summary/package fields.
        with tempfile.TemporaryDirectory() as tmp:
            req_path = Path(tmp) / "requirements.txt"
            req_path.write_text("requests==2.30.0\n", encoding="utf-8")
            original = self.module.run_outdated_list
            self.module.run_outdated_list = lambda: [
                {"name": "requests", "version": "2.30.0", "latest_version": "2.31.0"},
                {"name": "idna", "version": "3.6", "latest_version": "3.7"},
            ]
            try:
                report = self.module.make_report(req_path)
            finally:
                self.module.run_outdated_list = original
        self.assertEqual(report["summary"]["total_outdated"], 2)
        self.assertEqual(report["summary"]["direct_requirements_outdated"], 1)
        text = self.module.format_report_text(report)
        self.assertIn("Dependency freshness report", text)
        self.assertIn("requests", text)
        self.assertIn("transitive", text)

    def test_main_fails_for_configured_gates(self) -> None:
        #R010-T01: Verify each gate independently returns a failing exit status only when its configured condition is present.
        with tempfile.TemporaryDirectory() as tmp:
            req_path = Path(tmp) / "requirements.txt"
            out_json = Path(tmp) / "report.json"
            out_text = Path(tmp) / "report.txt"
            req_path.write_text("requests==2.30.0\n", encoding="utf-8")
            argv = sys.argv
            try:
                sys.argv = [
                    "check_dependency_freshness.py",
                    "--requirements",
                    str(req_path),
                    "--output-json",
                    str(out_json),
                    "--output-text",
                    str(out_text),
                    "--fail-on-any-actionable-outdated",
                    "--fail-on-major",
                    "--fail-on-direct-outdated",
                ]
                original = self.module.make_report
                self.module.make_report = lambda *_args: {
                    "generated_at": "2026-01-01T00:00:00+00:00",
                    "requirements_file": str(req_path),
                    "summary": {
                        "total_outdated": 1,
                        "major_updates": 1,
                        "minor_updates": 0,
                        "patch_updates": 0,
                        "unknown_updates": 0,
                        "direct_requirements_outdated": 1,
                        "actionable_outdated": 1,
                        "constrained_outdated": 0,
                        "unknown_actionability_outdated": 0,
                    },
                    "packages": [
                        {
                            "name": "requests",
                            "current_version": "2.30.0",
                            "latest_version": "3.0.0",
                            "update_type": "major",
                            "in_requirements_txt": True,
                            "is_exact_pin_in_requirements": True,
                        }
                    ],
                }
                rc = self.module.main()
            finally:
                self.module.make_report = original
                sys.argv = argv
            self.assertEqual(rc, 1)
            payload = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(payload["summary"]["major_updates"], 1)

    def test_main_fails_on_any_actionable_outdated_with_only_transitive_drift(self) -> None:
        #R010-T01: Verify each gate independently returns a failing exit status only when its configured condition is present.
        with tempfile.TemporaryDirectory() as tmp:
            req_path = Path(tmp) / "requirements.txt"
            out_json = Path(tmp) / "report.json"
            out_text = Path(tmp) / "report.txt"
            req_path.write_text("requests==2.30.0\n", encoding="utf-8")
            argv = sys.argv
            try:
                sys.argv = [
                    "check_dependency_freshness.py",
                    "--requirements",
                    str(req_path),
                    "--output-json",
                    str(out_json),
                    "--output-text",
                    str(out_text),
                    "--fail-on-any-actionable-outdated",
                ]
                original = self.module.make_report
                self.module.make_report = lambda *_args: {
                    "generated_at": "2026-01-01T00:00:00+00:00",
                    "requirements_file": str(req_path),
                    "summary": {
                        "total_outdated": 1,
                        "major_updates": 0,
                        "minor_updates": 1,
                        "patch_updates": 0,
                        "unknown_updates": 0,
                        "direct_requirements_outdated": 0,
                        "actionable_outdated": 1,
                        "constrained_outdated": 0,
                        "unknown_actionability_outdated": 0,
                    },
                    "packages": [
                        {
                            "name": "idna",
                            "current_version": "3.6",
                            "latest_version": "3.7",
                            "update_type": "minor",
                            "in_requirements_txt": False,
                            "is_exact_pin_in_requirements": False,
                            "outdated_actionability": "actionable",
                        }
                    ],
                }
                rc = self.module.main()
            finally:
                self.module.make_report = original
                sys.argv = argv
            self.assertEqual(rc, 1)

    def test_main_ignores_constrained_only_outdated_for_actionable_gate(self) -> None:
        #R010-T01: Verify each gate independently returns a failing exit status only when its configured condition is present.
        with tempfile.TemporaryDirectory() as tmp:
            req_path = Path(tmp) / "requirements.txt"
            out_json = Path(tmp) / "report.json"
            out_text = Path(tmp) / "report.txt"
            req_path.write_text("requests==2.30.0\n", encoding="utf-8")
            argv = sys.argv
            try:
                sys.argv = [
                    "check_dependency_freshness.py",
                    "--requirements",
                    str(req_path),
                    "--output-json",
                    str(out_json),
                    "--output-text",
                    str(out_text),
                    "--fail-on-any-actionable-outdated",
                ]
                original = self.module.make_report
                self.module.make_report = lambda *_args: {
                    "generated_at": "2026-01-01T00:00:00+00:00",
                    "requirements_file": str(req_path),
                    "summary": {
                        "total_outdated": 1,
                        "major_updates": 0,
                        "minor_updates": 1,
                        "patch_updates": 0,
                        "unknown_updates": 0,
                        "direct_requirements_outdated": 0,
                        "actionable_outdated": 0,
                        "constrained_outdated": 1,
                        "unknown_actionability_outdated": 0,
                    },
                    "packages": [
                        {
                            "name": "mando",
                            "current_version": "0.7.1",
                            "latest_version": "0.8.2",
                            "update_type": "minor",
                            "in_requirements_txt": False,
                            "is_exact_pin_in_requirements": False,
                            "outdated_actionability": "constrained",
                        }
                    ],
                }
                rc = self.module.main()
            finally:
                self.module.make_report = original
                sys.argv = argv
            self.assertEqual(rc, 0)

    def test_main_fails_when_venv_cruft_gate_enabled(self) -> None:
        #R010-T01: Verify each gate independently returns a failing exit status only when its configured condition is present.
        with tempfile.TemporaryDirectory() as tmp:
            req_path = Path(tmp) / "requirements.txt"
            out_json = Path(tmp) / "report.json"
            out_text = Path(tmp) / "report.txt"
            req_path.write_text("requests==2.30.0\n", encoding="utf-8")
            argv = sys.argv
            try:
                sys.argv = [
                    "check_dependency_freshness.py",
                    "--requirements",
                    str(req_path),
                    "--output-json",
                    str(out_json),
                    "--output-text",
                    str(out_text),
                    "--fail-on-venv-cruft",
                ]
                original = self.module.make_report
                self.module.make_report = lambda *_args: {
                    "generated_at": "2026-01-01T00:00:00+00:00",
                    "requirements_file": str(req_path),
                    "summary": {
                        "total_outdated": 0,
                        "major_updates": 0,
                        "minor_updates": 0,
                        "patch_updates": 0,
                        "unknown_updates": 0,
                        "direct_requirements_outdated": 0,
                        "actionable_outdated": 0,
                        "constrained_outdated": 0,
                        "unknown_actionability_outdated": 0,
                    },
                    "packages": [],
                    "venv_cruft_packages": ["semgrep"],
                    "venv_cruft_status": "ok",
                }
                rc = self.module.main()
            finally:
                self.module.make_report = original
                sys.argv = argv
            self.assertEqual(rc, 1)


class CheckDependencyFreshnessShard1TraceabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        #R001: Cover traceability for this helper/test behavior.
        cls.module = load_module()

    def test_r220_traceability_anchor(self) -> None:
        #R220-T01: Validate normalize package helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "normalize_package_name")))

    def test_r221_traceability_anchor(self) -> None:
        #R221-T01: Validate requirements parser helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_requirements")))

    def test_r222_traceability_anchor(self) -> None:
        #R222-T01: Validate version triplet helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_version_triplet")))

    def test_r223_traceability_anchor(self) -> None:
        #R223-T01: Validate update classifier helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "classify_update")))

    def test_r224_traceability_anchor(self) -> None:
        #R224-T01: Validate outdated list helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "run_outdated_list")))

    def test_r225_traceability_anchor(self) -> None:
        #R225-T01: Validate reverse constraints helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_collect_reverse_dependency_constraints")))

    def test_r226_traceability_anchor(self) -> None:
        #R226-T01: Validate requested package helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_collect_requested_packages")))

    def test_r227_traceability_anchor(self) -> None:
        #R227-T01: Validate venv cruft helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_detect_venv_cruft")))

    def test_r228_traceability_anchor(self) -> None:
        #R228-T01: Validate actionability helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_evaluate_actionability")))

    def test_r229_traceability_anchor(self) -> None:
        #R229-T01: Validate package entry builder helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_package_entry_from_outdated_row")))

    def test_r230_traceability_anchor(self) -> None:
        #R230-T01: Validate summary builder helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_build_summary")))

    def test_r231_traceability_anchor(self) -> None:
        #R231-T01: Validate direct requirements helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_load_direct_requirements")))

    def test_r232_traceability_anchor(self) -> None:
        #R232-T01: Validate report builder helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "make_report")))

    def test_r233_traceability_anchor(self) -> None:
        #R233-T01: Validate report formatter helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "format_report_text")))

    def test_r234_traceability_anchor(self) -> None:
        #R234-T01: Validate parser helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_args")))

    def test_r235_traceability_anchor(self) -> None:
        #R235-T01: Validate main helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "main")))

if __name__ == "__main__":
    unittest.main()
