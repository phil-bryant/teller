#            restores the database back to that snapshot end-to-end.

"""Opt-in integration test for the DAST baseline + cleanup hygiene contract.

Skipped by default. Enable by setting `RUN_DAST_DB_HYGIENE_TEST=true` and
ensuring the active `teller_db` profile points at a writable dev database
(typically `local`). The test:
    1. Captures a baseline via `src/scripts/dast_baseline.py`.
    2. Mutates the database the same way `23_` does (INSERT a non-seed
       category, UPDATE an existing non-seed category if any, mutate or
       insert a `transaction_email_match` row).
    3. Runs `src/scripts/dast_cleanup.py` and asserts that the post-cleanup
       row hashes match the pre-mutation baseline hashes for each of the
       four affected tables.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import uuid

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE_SCRIPT = REPO_ROOT / "src" / "scripts" / "dast_baseline.py"
CLEANUP_SCRIPT = REPO_ROOT / "src" / "scripts" / "dast_cleanup.py"

ENABLED = os.environ.get("RUN_DAST_DB_HYGIENE_TEST", "false").lower() == "true"


@unittest.skipUnless(ENABLED, "RUN_DAST_DB_HYGIENE_TEST != 'true'")
class TestDastBaselineAndCleanup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        #R001: Cover traceability for this helper/test behavior.
        sys.path.insert(0, str(REPO_ROOT / "src"))
        from teller.teller_db import get_engine

        cls.engine = get_engine()

    def _hash_state(self) -> dict[str, str]:
        #R001: Cover traceability for this helper/test behavior.
        from sqlalchemy import text

        queries = {
            "nys_snw_category": "SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name, level_3, level_4, categorization, applicability, is_seed FROM teller.nys_snw_category ORDER BY nys_snw_category_id",
            "transaction_email_match": "SELECT match_id, transaction_id, email_message_id, state::text, ai_confidence::text, selected_by::text, selected_at, moved_to_matchy_at, active, updated_at FROM teller.transaction_email_match ORDER BY match_id",
            "transaction_email_match_audit": "SELECT match_audit_id, match_id, from_state::text, to_state::text, actor::text, note, created_at FROM teller.transaction_email_match_audit ORDER BY match_audit_id",
            "transaction_nys_snw_category": "SELECT transaction_id, nys_snw_category_id, type::text FROM teller.transaction_nys_snw_category ORDER BY transaction_id",
        }
        hashes = {}
        with self.engine.connect() as conn:
            for table, sql in queries.items():
                rows = conn.execute(text(sql)).fetchall()
                blob = repr([tuple(str(value) for value in row) for row in rows])
                hashes[table] = hashlib.sha256(blob.encode("utf-8")).hexdigest()
        return hashes

    def _run(self, script: pathlib.Path, *args: str) -> str:
        #R001: Cover traceability for this helper/test behavior.
        env = os.environ.copy()
        existing = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = (
            f"{REPO_ROOT / 'src'}:{REPO_ROOT}:{existing}" if existing else f"{REPO_ROOT / 'src'}:{REPO_ROOT}"
        )
        completed = subprocess.run(
            [sys.executable, str(script), *args],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        if completed.returncode != 0:
            self.fail(
                f"{script.name} failed (rc={completed.returncode}):\n"
                f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
            )
        return completed.stdout

    def test_cleanup_restores_pre_baseline_state(self):
        #R001: Cover traceability for this helper/test behavior.
        from sqlalchemy import text

        run_id = f"dast-test-{uuid.uuid4().hex[:8]}"

        pre_hashes = self._hash_state()

        with tempfile.TemporaryDirectory() as tmp:
            baseline_path = pathlib.Path(tmp) / "baseline.json"
            summary_path = pathlib.Path(tmp) / "summary.json"

            self._run(BASELINE_SCRIPT, str(baseline_path))

            with self.engine.begin() as conn:
                conn.execute(
                    text(
                        """
                        INSERT INTO teller.nys_snw_category (
                            level_1, level_1_name, level_2, level_2_name,
                            level_3, level_4, categorization, applicability
                        ) VALUES (
                            'DAST', 'DAST Test', 'Hygiene', 'Hygiene',
                            'Unit', :level_4, :categorization, :applicability
                        )
                        """
                    ),
                    {
                        "level_4": f"Insert {run_id}",
                        "categorization": f"Runtime [{run_id}]",
                        "applicability": f"hygiene-{run_id}",
                    },
                )

            mid_hashes = self._hash_state()
            self.assertNotEqual(
                pre_hashes["nys_snw_category"],
                mid_hashes["nys_snw_category"],
                "mutation step did not change nys_snw_category hash",
            )

            self._run(CLEANUP_SCRIPT, str(baseline_path), run_id, str(summary_path))
            summary = (
                json.loads(summary_path.read_text(encoding="utf-8"))
                if summary_path.exists()
                else {}
            )

        post_hashes = self._hash_state()
        self.assertEqual(pre_hashes, post_hashes, "cleanup did not restore pre-baseline state")
        self.assertEqual(summary.get("status"), "applied", summary)


if __name__ == "__main__":
    unittest.main()
