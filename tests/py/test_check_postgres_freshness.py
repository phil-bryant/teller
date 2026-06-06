#!/usr/bin/env python3

import json
import os
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


class CheckPostgresFreshnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[2]
        self.script_path = self.repo_root / "src" / "scripts" / "check_postgres_freshness.py"
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)
        self.stub_bin = self.tmp_path / "bin"
        self.stub_bin.mkdir(parents=True, exist_ok=True)
        self._write_psql_stub()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write_psql_stub(self) -> None:
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


if __name__ == "__main__":
    unittest.main()
