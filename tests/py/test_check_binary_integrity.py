#!/usr/bin/env python3

import importlib.util
import json
import stat
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "src" / "scripts" / "check_binary_integrity.py"
    spec = importlib.util.spec_from_file_location("check_binary_integrity", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load check_binary_integrity module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def make_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    current = path.stat().st_mode
    path.chmod(current | stat.S_IXUSR)


class CheckBinaryIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_make_report_detects_missing_and_version_stale(self) -> None:
        #R001-T01: Evaluate a policy with present and missing commands and verify report includes executable path, version, and hash fields (`tests/py/test_check_binary_integrity.py`).
        #R005-T01: Verify report generation counts missing required and stale-version statuses correctly (`tests/py/test_check_binary_integrity.py`).
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fake_bin = tmp_path / "fake-tool"
            make_executable(
                fake_bin,
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    echo "fake-tool version 1.0.0"
                    """
                ),
            )
            policy_path = tmp_path / "policy.json"
            policy_path.write_text(
                json.dumps(
                    {
                        "binaries": [
                            {
                                "id": "missing-required",
                                "command": "definitely-not-on-path-xyz",
                                "required": True,
                                "version_args": ["--version"],
                                "version_pattern": "(\\d+\\.\\d+\\.\\d+)",
                                "min_version": "1.0.0",
                                "allowed_sha256": [],
                            },
                            {
                                "id": "stale-tool",
                                "command": str(fake_bin),
                                "required": True,
                                "version_args": ["--version"],
                                "version_pattern": "(\\d+\\.\\d+\\.\\d+)",
                                "min_version": "2.0.0",
                                "allowed_sha256": [],
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            report = self.module.make_report(policy_path)
        self.assertEqual(report["summary"]["missing_required"], 1)
        self.assertEqual(report["summary"]["version_stale"], 1)
        statuses = {entry["id"]: entry["status"] for entry in report["binaries"]}
        self.assertEqual(statuses["missing-required"], "missing")
        self.assertEqual(statuses["stale-tool"], "version_stale")

    def test_main_fails_on_hash_mismatch_when_enabled(self) -> None:
        #R010-T01: Verify `main()` returns failing exit status only when the corresponding strict gate is enabled and its condition is present (`tests/py/test_check_binary_integrity.py`).
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fake_bin = tmp_path / "fake-hash-tool"
            make_executable(
                fake_bin,
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    echo "fake-hash-tool 3.2.1"
                    """
                ),
            )
            policy_path = tmp_path / "policy.json"
            out_json = tmp_path / "report.json"
            out_text = tmp_path / "report.txt"
            policy_path.write_text(
                json.dumps(
                    {
                        "binaries": [
                            {
                                "id": "hash-tool",
                                "command": str(fake_bin),
                                "required": True,
                                "version_args": ["--version"],
                                "version_pattern": "(\\d+\\.\\d+\\.\\d+)",
                                "min_version": "1.0.0",
                                "allowed_sha256": ["0" * 64],
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            argv = sys.argv
            try:
                sys.argv = [
                    "check_binary_integrity.py",
                    "--policy",
                    str(policy_path),
                    "--output-json",
                    str(out_json),
                    "--output-text",
                    str(out_text),
                    "--fail-on-hash",
                ]
                rc = self.module.main()
            finally:
                sys.argv = argv
            self.assertEqual(rc, 1)
            payload = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(payload["summary"]["hash_mismatch"], 1)

    def test_make_report_marks_hash_allowlist_match_ok(self) -> None:
        #R015-T01: Verify a digest in `allowed_sha256` produces an `ok` hash status and no hash mismatch count (`tests/py/test_check_binary_integrity.py`).
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fake_bin = tmp_path / "fake-hash-ok-tool"
            make_executable(
                fake_bin,
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    echo "fake-hash-ok-tool 1.2.3"
                    """
                ),
            )
            expected_digest = self.module.sha256_file(str(fake_bin))
            policy_path = tmp_path / "policy.json"
            policy_path.write_text(
                json.dumps(
                    {
                        "binaries": [
                            {
                                "id": "hash-ok-tool",
                                "command": str(fake_bin),
                                "required": True,
                                "version_args": ["--version"],
                                "version_pattern": "(\\d+\\.\\d+\\.\\d+)",
                                "min_version": None,
                                "allowed_sha256": [expected_digest.upper()],
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            report = self.module.make_report(policy_path)
        self.assertEqual(report["summary"]["hash_mismatch"], 0)
        entry = report["binaries"][0]
        self.assertEqual(entry["status"], "ok")
        self.assertEqual(entry["hash_status"], "ok")

    def test_main_passes_without_failure_flags(self) -> None:
        #R010-T01: Verify `main()` returns failing exit status only when the corresponding strict gate is enabled and its condition is present (`tests/py/test_check_binary_integrity.py`).
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fake_bin = tmp_path / "optional-tool"
            make_executable(
                fake_bin,
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    echo "optional-tool 1.0.0"
                    """
                ),
            )
            policy_path = tmp_path / "policy.json"
            out_json = tmp_path / "report.json"
            out_text = tmp_path / "report.txt"
            policy_path.write_text(
                json.dumps(
                    {
                        "binaries": [
                            {
                                "id": "optional-tool",
                                "command": str(fake_bin),
                                "required": False,
                                "version_args": ["--version"],
                                "version_pattern": "(\\d+\\.\\d+\\.\\d+)",
                                "min_version": None,
                                "allowed_sha256": [],
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            argv = sys.argv
            try:
                sys.argv = [
                    "check_binary_integrity.py",
                    "--policy",
                    str(policy_path),
                    "--output-json",
                    str(out_json),
                    "--output-text",
                    str(out_text),
                ]
                rc = self.module.main()
            finally:
                sys.argv = argv
            self.assertEqual(rc, 0)
            self.assertTrue(out_text.exists())


if __name__ == "__main__":
    unittest.main()
