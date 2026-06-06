#!/usr/bin/env python3

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


class CheckPostgresFreshnessTests(unittest.TestCase):
    def setUp(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        self.repo_root = Path(__file__).resolve().parents[2]
        self.script_path = self.repo_root / "src" / "scripts" / "check_postgres_freshness.py"
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)
        self.stub_bin = self.tmp_path / "bin"
        self.stub_bin.mkdir(parents=True, exist_ok=True)
        self._write_psql_stub()

    def tearDown(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        self.temp_dir.cleanup()

    def _write_psql_stub(self) -> None:
        #R020: Cover traceability for this helper/test behavior.
        stub_path = self.stub_bin / "psql"
        stub_path.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"$1\" == \"--version\" ]]; then\n"
            "  echo \"psql (PostgreSQL) ${PSQL_CLIENT_VERSION:-16.2}\"\n"
            "  exit 0\n"
            "fi\n"
            "if [[ \"${PSQL_SERVER_QUERY_EXIT:-0}\" != \"0\" && \" $* \" == *\" -tAc \"* ]]; then\n"
            "  echo \"${PSQL_SERVER_QUERY_ERROR:-server query failed}\" >&2\n"
            "  exit \"${PSQL_SERVER_QUERY_EXIT}\"\n"
            "fi\n"
            "if [[ \"$1\" == \"-tAc\" ]]; then\n"
            "  echo \"${PSQL_SERVER_VERSION_NUM:-160002}\"\n"
            "  exit 0\n"
            "fi\n"
            "if [[ \"$2\" == \"-tAc\" ]]; then\n"
            "  echo \"${PSQL_SERVER_VERSION_NUM:-160002}\"\n"
            "  exit 0\n"
            "fi\n"
            "echo \"unsupported psql invocation\" >&2\n"
            "exit 1\n",
            encoding="utf-8",
        )
        stub_path.chmod(0o755)

    def _run_checker(self, snapshot: dict, policy: dict, extra_args: list[str] | None = None) -> tuple[int, dict]:
        #R020: Cover traceability for this helper/test behavior.
        snapshot_path = self.tmp_path / "snapshot.json"
        policy_path = self.tmp_path / "policy.json"
        output_json = self.tmp_path / "report.json"
        output_text = self.tmp_path / "report.txt"

        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
        policy_path.write_text(json.dumps(policy), encoding="utf-8")

        cmd = [
            "python3",
            str(self.script_path),
            "--output-json",
            str(output_json),
            "--output-text",
            str(output_text),
            "--check-cves",
            "--fail-on-cve",
            "--cve-snapshot",
            str(snapshot_path),
            "--cve-policy",
            str(policy_path),
        ]
        if extra_args:
            cmd.extend(extra_args)

        env = os.environ.copy()
        env["PATH"] = f"{self.stub_bin}:{env.get('PATH', '')}"
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env, check=False)
        report = json.loads(output_json.read_text(encoding="utf-8"))
        return proc.returncode, report

    def test_fail_on_matching_cve_range(self) -> None:
        #R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.
        snapshot = {
            "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cves": [
                {
                    "id": "CVE-TEST-0001",
                    "severity": "critical",
                    "affected": [
                        {
                            "component": "client",
                            "ranges": [">=16.0,<16.3"],
                            "fixed_versions": ["16.3"],
                        }
                    ],
                }
            ],
        }
        policy = {
            "severity_threshold": "high",
            "max_snapshot_age_hours": 168,
            "fail_on_stale_snapshot": False,
        }

        code, report = self._run_checker(snapshot=snapshot, policy=policy)
        self.assertEqual(code, 1)
        self.assertTrue(report["summary"]["gate_failed"])
        self.assertEqual(len(report["cve"]["vulnerabilities"]), 1)
        self.assertEqual(report["cve"]["vulnerabilities"][0]["component"], "client")

    def test_pass_when_versions_not_in_affected_ranges(self) -> None:
        #R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.
        snapshot = {
            "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cves": [
                {
                    "id": "CVE-TEST-0002",
                    "severity": "high",
                    "affected": [
                        {
                            "component": "client",
                            "ranges": [">=16.3,<16.4"],
                            "fixed_versions": ["16.4"],
                        }
                    ],
                }
            ],
        }
        policy = {
            "severity_threshold": "high",
            "max_snapshot_age_hours": 168,
            "fail_on_stale_snapshot": False,
        }

        code, report = self._run_checker(snapshot=snapshot, policy=policy)
        self.assertEqual(code, 0)
        self.assertFalse(report["summary"]["gate_failed"])
        self.assertEqual(report["cve"]["vulnerabilities"], [])

    def test_stale_snapshot_can_fail_policy(self) -> None:
        #R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.
        old_ts = datetime.now(timezone.utc) - timedelta(days=30)
        snapshot = {
            "generated_at": old_ts.isoformat().replace("+00:00", "Z"),
            "cves": [],
        }
        policy = {
            "severity_threshold": "high",
            "max_snapshot_age_hours": 24,
            "fail_on_stale_snapshot": True,
        }

        code, report = self._run_checker(snapshot=snapshot, policy=policy)
        self.assertEqual(code, 1)
        self.assertTrue(report["cve"]["snapshot_stale"])
        self.assertTrue(report["summary"]["gate_failed"])

    def test_empty_snapshot_reports_inconclusive_assurance(self) -> None:
        #R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.
        snapshot = {
            "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cves": [],
        }
        policy = {
            "severity_threshold": "high",
            "max_snapshot_age_hours": 168,
            "fail_on_stale_snapshot": False,
        }

        code, report = self._run_checker(snapshot=snapshot, policy=policy)
        self.assertEqual(code, 0)
        self.assertEqual(report["cve"]["status"], "inconclusive")
        self.assertEqual(report["cve"]["assurance"], "empty-snapshot")
        self.assertFalse(report["summary"]["gate_failed"])

    def test_server_version_num_for_pg16_parses_minor_correctly(self) -> None:
        #R025-T01: Verify CVE matching, severity thresholds, stale snapshot handling, and fail-on-CVE behavior.
        snapshot = {
            "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cves": [
                {
                    "id": "CVE-TEST-SERVER-15",
                    "severity": "critical",
                    "affected": [
                        {
                            "component": "server",
                            "ranges": [">=15.0,<15.16"],
                            "fixed_versions": ["15.16"],
                        }
                    ],
                }
            ],
        }
        policy = {
            "severity_threshold": "high",
            "max_snapshot_age_hours": 168,
            "fail_on_stale_snapshot": False,
        }
        prior_server_num = os.environ.get("PSQL_SERVER_VERSION_NUM")
        os.environ["PSQL_SERVER_VERSION_NUM"] = "150017"
        try:
            code, report = self._run_checker(
                snapshot=snapshot,
                policy=policy,
                extra_args=["--check-server-version", "--server-dsn", "postgresql://example"],
            )
        finally:
            if prior_server_num is None:
                os.environ.pop("PSQL_SERVER_VERSION_NUM", None)
            else:
                os.environ["PSQL_SERVER_VERSION_NUM"] = prior_server_num
        self.assertEqual(code, 0)
        self.assertEqual(report["server"]["version"], "15.17.0")
        self.assertEqual(report["cve"]["vulnerabilities"], [])

    def test_server_warning_includes_attempted_target_details(self) -> None:
        #R020-T01: Verify client/server version parsing and stale-component gating for compliant and non-compliant versions.
        snapshot = {
            "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cves": [],
        }
        policy = {
            "severity_threshold": "high",
            "max_snapshot_age_hours": 168,
            "fail_on_stale_snapshot": False,
        }
        prior_query_exit = os.environ.get("PSQL_SERVER_QUERY_EXIT")
        prior_query_error = os.environ.get("PSQL_SERVER_QUERY_ERROR")
        os.environ["PSQL_SERVER_QUERY_EXIT"] = "2"
        os.environ["PSQL_SERVER_QUERY_ERROR"] = "connection refused"
        try:
            _, report = self._run_checker(
                snapshot=snapshot,
                policy=policy,
                extra_args=["--check-server-version", "--server-psql-args=-h dbhost -U teller -d prod"],
            )
        finally:
            if prior_query_exit is None:
                os.environ.pop("PSQL_SERVER_QUERY_EXIT", None)
            else:
                os.environ["PSQL_SERVER_QUERY_EXIT"] = prior_query_exit
            if prior_query_error is None:
                os.environ.pop("PSQL_SERVER_QUERY_ERROR", None)
            else:
                os.environ["PSQL_SERVER_QUERY_ERROR"] = prior_query_error
        joined_warnings = "\n".join(report["summary"]["warnings"])
        self.assertIn("attempted psql args: -h dbhost -U teller -d prod", joined_warnings)
        self.assertEqual(report["server"]["status"], "error")
        self.assertIn("connection refused", report["server"]["error"])


class CheckPostgresFreshnessShard1TraceabilityTests(unittest.TestCase):
    @staticmethod
    def _load_module():
        #R020: Cover traceability for this helper/test behavior.
        repo_root = Path(__file__).resolve().parents[2]
        script_path = repo_root / "src" / "scripts" / "check_postgres_freshness.py"
        spec = importlib.util.spec_from_file_location("check_postgres_freshness", script_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("Unable to load check_postgres_freshness module")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module

    @classmethod
    def setUpClass(cls) -> None:
        #R020: Cover traceability for this helper/test behavior.
        cls.module = cls._load_module()

    def test_r240_traceability_anchor(self) -> None:
        #R240-T01: Validate semver helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_semver")))
        self.assertTrue(callable(getattr(self.module, "compare_semver")))

    def test_r241_traceability_anchor(self) -> None:
        #R241-T01: Validate postgres version parsers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_psql_client_version")))
        self.assertTrue(callable(getattr(self.module, "parse_server_version_num")))

    def test_r242_traceability_anchor(self) -> None:
        #R242-T01: Validate meets-minimum helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "meets_minimum")))

    def test_r243_traceability_anchor(self) -> None:
        #R243-T01: Validate severity helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "normalize_severity")))
        self.assertTrue(callable(getattr(self.module, "severity_meets_threshold")))

    def test_r244_traceability_anchor(self) -> None:
        #R244-T01: Validate ISO parser helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_iso_datetime")))

    def test_r245_traceability_anchor(self) -> None:
        #R245-T01: Validate constraint helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "satisfies_constraint")))
        self.assertTrue(callable(getattr(self.module, "satisfies_range")))
        self.assertTrue(callable(getattr(self.module, "version_in_any_range")))

    def test_r246_traceability_anchor(self) -> None:
        #R246-T01: Validate JSON reader helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "read_json_file")))

    def test_r247_traceability_anchor(self) -> None:
        #R247-T01: Validate snapshot decision helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "should_write_refreshed_snapshot")))

    def test_r248_traceability_anchor(self) -> None:
        #R248-T01: Validate component scope helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "component_to_scope")))

    def test_r249_traceability_anchor(self) -> None:
        #R249-T01: Validate score severity helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "score_to_severity")))

    def test_r250_traceability_anchor(self) -> None:
        #R250-T01: Validate strip HTML helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "strip_html")))

    def test_r251_traceability_anchor(self) -> None:
        #R251-T01: Validate major helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "extract_major")))
        self.assertTrue(callable(getattr(self.module, "validate_postgresql_major")))

    def test_r252_traceability_anchor(self) -> None:
        #R252-T01: Validate security page fetch helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "fetch_postgresql_security_page")))

    def test_r253_traceability_anchor(self) -> None:
        #R253-T01: Validate cve snapshot helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "fetch_postgresql_cve_snapshot")))

    def test_r254_traceability_anchor(self) -> None:
        #R254-T01: Validate initial cve result helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_initial_cve_result")))

    def test_r255_traceability_anchor(self) -> None:
        #R255-T01: Validate cve policy helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_load_cve_policy")))

    def test_r256_traceability_anchor(self) -> None:
        #R256-T01: Validate refresh/load helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_refresh_or_load_snapshot")))

    def test_r257_traceability_anchor(self) -> None:
        #R257-T01: Validate policy-failed helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_mark_policy_failed")))

    def test_r258_traceability_anchor(self) -> None:
        #R258-T01: Validate snapshot freshness helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_apply_snapshot_freshness")))

    def test_r259_traceability_anchor(self) -> None:
        #R259-T01: Validate findings helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "_collect_cve_findings")))
        self.assertTrue(callable(getattr(self.module, "_findings_for_spec")))

    def test_r260_traceability_anchor(self) -> None:
        #R260-T01: Validate server command helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_build_server_version_command")))

    def test_r261_traceability_anchor(self) -> None:
        #R261-T01: Validate version check helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "_check_client_version")))
        self.assertTrue(callable(getattr(self.module, "_check_server_version")))

    def test_r262_traceability_anchor(self) -> None:
        #R262-T01: Validate cve entry validator helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_validate_cve_entries")))

    def test_r263_traceability_anchor(self) -> None:
        #R263-T01: Validate summary merge helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_merge_cve_summary")))

    def test_r264_traceability_anchor(self) -> None:
        #R264-T01: Validate base report lines helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_base_report_lines")))

    def test_r265_traceability_anchor(self) -> None:
        #R265-T01: Validate info initializer helpers are callable and anchored
        self.assertTrue(callable(getattr(self.module, "_initial_client_info")))
        self.assertTrue(callable(getattr(self.module, "_initial_server_info")))

    def test_r266_traceability_anchor(self) -> None:
        #R266-T01: Validate policy-from-args helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "_policy_from_args")))

    def test_r267_traceability_anchor(self) -> None:
        #R267-T01: Validate evaluate CVEs helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "evaluate_cves")))

    def test_r268_traceability_anchor(self) -> None:
        #R268-T01: Validate run command helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "run_command")))

    def test_r269_traceability_anchor(self) -> None:
        #R269-T01: Validate target description helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "describe_server_target")))

    def test_r270_traceability_anchor(self) -> None:
        #R270-T01: Validate report builder helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "build_report")))

    def test_r271_traceability_anchor(self) -> None:
        #R271-T01: Validate text report helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "format_text_report")))

    def test_r272_traceability_anchor(self) -> None:
        #R272-T01: Validate parser helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "parse_args")))

    def test_r273_traceability_anchor(self) -> None:
        #R273-T01: Validate main helper is callable and anchored
        self.assertTrue(callable(getattr(self.module, "main")))

if __name__ == "__main__":
    unittest.main()
