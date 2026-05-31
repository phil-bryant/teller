#!/usr/bin/env python3
#R001: Restore baseline-captured mutable data and delete post-baseline inserts transactionally.
#R005: Refuse cleanup when baseline profile mismatches active profile unless force-enabled.
#R010: Handle missing/non-captured baselines as non-fatal skips with diagnostics.
"""Restore the database to the pre-DAST baseline captured by dast_baseline.py.

The companion to tests/t12_run_dynamic_security_tests.sh's EXIT trap. Runs:
    1. Restore mutated transaction_email_match rows back to baseline state.
    2. Delete audit rows inserted during the run.
    3. Delete transaction_email_match rows inserted during the run (cascades audit).
    4. Reconcile transaction_nys_snw_category: delete rows not in baseline,
       upsert rows present in baseline back to baseline values.
    5. Delete non-seed nys_snw_category rows inserted during the run, plus
       any non-seed row tagged with the per-run DAST_RUN_ID as a defensive
       sweep for seeded rows that may have been mutated in place.
    6. Restore non-seed nys_snw_category rows that existed in baseline to
       their baseline values (in case PUT mutated them).

The whole run executes in a single transaction; any exception rolls back
and leaves the DB in whatever state it was prior to cleanup. Errors are
written to the summary JSON for forensics but never propagated unless
the safety guard refuses to run.

Safety guard: refuses to apply when the baseline's recorded
``profile_name`` differs from the current resolved profile, unless
``DAST_CLEANUP_FORCE=true`` is set.

Usage:
    dast_cleanup.py <baseline_json_path> <run_id> <summary_json_path>
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import text


def _load_baseline(path: pathlib.Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _write_summary(path: pathlib.Path, summary: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, default=str)
        fh.write("\n")


def _emit_summary(summary_path: pathlib.Path, summary: dict[str, Any], payload: dict[str, Any], exit_code: int) -> int:
    _write_summary(summary_path, summary)
    print(json.dumps(payload))
    return exit_code


def _skip_with_error(summary: dict[str, Any], summary_path: pathlib.Path, error: str) -> int:
    summary["status"] = "skipped"
    summary["errors"].append(error)
    return _emit_summary(
        summary_path,
        summary,
        {"status": summary["status"], "errors": summary["errors"]},
        0,
    )


def _refuse_with_error(summary: dict[str, Any], summary_path: pathlib.Path, error: str) -> int:
    summary["status"] = "refused"
    summary["errors"].append(error)
    return _emit_summary(
        summary_path,
        summary,
        {"status": summary["status"], "errors": summary["errors"]},
        1,
    )


def _restore_matches(conn, matches_baseline: list[dict[str, Any]], baseline_max_match_id: int) -> int:
    restored_matches = 0
    for match in matches_baseline:
        match_id = int(match["match_id"])
        if match_id > baseline_max_match_id:
            continue
        result = conn.execute(
            text(
                """
                UPDATE teller.transaction_email_match
                   SET email_message_id = :email_message_id,
                       state = CAST(:state AS teller.transaction_email_match_state),
                       ai_confidence = CAST(:ai_confidence AS DECIMAL(5,4)),
                       selected_by = CAST(:selected_by AS teller.transaction_email_match_selected_by),
                       selected_at = :selected_at,
                       moved_to_matchy_at = :moved_to_matchy_at,
                       active = :active,
                       updated_at = :updated_at
                 WHERE match_id = :match_id
                """
            ),
            {
                "match_id": match_id,
                "email_message_id": match.get("email_message_id"),
                "state": match.get("state"),
                "ai_confidence": match.get("ai_confidence"),
                "selected_by": match.get("selected_by"),
                "selected_at": match.get("selected_at"),
                "moved_to_matchy_at": match.get("moved_to_matchy_at"),
                "active": bool(match.get("active")),
                "updated_at": match.get("updated_at"),
            },
        )
        restored_matches += result.rowcount or 0
    return restored_matches


def _delete_post_baseline_audits(conn, baseline_max_match_audit_id: int) -> int:
    return conn.execute(
        text(
            """
            DELETE FROM teller.transaction_email_match_audit
             WHERE match_audit_id > :baseline_max_match_audit_id
            """
        ),
        {"baseline_max_match_audit_id": baseline_max_match_audit_id},
    ).rowcount or 0


def _delete_post_baseline_matches(conn, baseline_max_match_id: int) -> int:
    return conn.execute(
        text(
            """
            DELETE FROM teller.transaction_email_match
             WHERE match_id > :baseline_max_match_id
            """
        ),
        {"baseline_max_match_id": baseline_max_match_id},
    ).rowcount or 0


def _reconcile_classifications(conn, classifications_baseline: list[dict[str, Any]]) -> tuple[int, int]:
    baseline_classification_tx = {row["transaction_id"] for row in classifications_baseline}
    if baseline_classification_tx:
        deleted_classifications = conn.execute(
            text(
                """
                DELETE FROM teller.transaction_nys_snw_category
                 WHERE NOT (transaction_id = ANY(:baseline_tx_ids))
                """
            ),
            {"baseline_tx_ids": sorted(baseline_classification_tx)},
        ).rowcount or 0
    else:
        deleted_classifications = conn.execute(
            text("DELETE FROM teller.transaction_nys_snw_category")
        ).rowcount or 0

    restored_classifications = 0
    for row in classifications_baseline:
        result = conn.execute(
            text(
                """
                INSERT INTO teller.transaction_nys_snw_category (
                    transaction_id, nys_snw_category_id, type
                ) VALUES (
                    :transaction_id,
                    :nys_snw_category_id,
                    CAST(:type AS teller.transaction_categorization_method)
                )
                ON CONFLICT (transaction_id) DO UPDATE
                   SET nys_snw_category_id = EXCLUDED.nys_snw_category_id,
                       type = EXCLUDED.type,
                       updated_at = CURRENT_TIMESTAMP
                """
            ),
            {
                "transaction_id": row["transaction_id"],
                "nys_snw_category_id": int(row["nys_snw_category_id"]),
                "type": row.get("type"),
            },
        )
        restored_classifications += result.rowcount or 0
    return deleted_classifications, restored_classifications


def _delete_post_baseline_categories(conn, baseline_max_category_id: int, run_id: str) -> int:
    return conn.execute(
        text(
            """
            DELETE FROM teller.nys_snw_category
             WHERE is_seed = FALSE
               AND (
                    nys_snw_category_id > :baseline_max_category_id
                    OR (categorization IS NOT NULL AND categorization LIKE :tag_pattern)
                   )
            """
        ),
        {
            "baseline_max_category_id": baseline_max_category_id,
            "tag_pattern": f"%[{run_id}]%",
        },
    ).rowcount or 0


def _restore_categories(conn, categories_baseline: list[dict[str, Any]], baseline_max_category_id: int) -> int:
    restored_categories = 0
    for row in categories_baseline:
        if bool(row.get("is_seed")):
            continue
        category_id = int(row["nys_snw_category_id"])
        if category_id > baseline_max_category_id:
            continue
        result = conn.execute(
            text(
                """
                UPDATE teller.nys_snw_category
                   SET level_1 = :level_1,
                       level_1_name = :level_1_name,
                       level_2 = :level_2,
                       level_2_name = :level_2_name,
                       level_3 = :level_3,
                       level_4 = :level_4,
                       categorization = :categorization,
                       applicability = :applicability,
                       updated_at = CURRENT_TIMESTAMP
                 WHERE nys_snw_category_id = :nys_snw_category_id
                   AND is_seed = FALSE
                """
            ),
            {
                "nys_snw_category_id": category_id,
                "level_1": row.get("level_1"),
                "level_1_name": row.get("level_1_name"),
                "level_2": row.get("level_2"),
                "level_2_name": row.get("level_2_name"),
                "level_3": row.get("level_3"),
                "level_4": row.get("level_4"),
                "categorization": row.get("categorization"),
                "applicability": row.get("applicability"),
            },
        )
        restored_categories += result.rowcount or 0
    return restored_categories


def _profile_refusal_message(baseline_profile: str | None, current_profile_name: str) -> str | None:
    if not baseline_profile:
        return None
    force_cleanup = os.environ.get("DAST_CLEANUP_FORCE", "false").lower() == "true"
    if baseline_profile == current_profile_name or force_cleanup:
        return None
    return (
        f"baseline profile {baseline_profile!r} does not match current profile "
        f"{current_profile_name!r}; refusing to run. "
        "Set DAST_CLEANUP_FORCE=true to override."
    )


def _run_cleanup_transaction(
    engine,
    *,
    matches_baseline: list[dict[str, Any]],
    classifications_baseline: list[dict[str, Any]],
    categories_baseline: list[dict[str, Any]],
    baseline_max_match_id: int,
    baseline_max_match_audit_id: int,
    baseline_max_category_id: int,
    run_id: str,
) -> dict[str, int]:
    counts: dict[str, int] = {}
    with engine.begin() as conn:
        counts["matches_restored"] = _restore_matches(conn, matches_baseline, baseline_max_match_id)
        counts["match_audit_rows_deleted"] = _delete_post_baseline_audits(conn, baseline_max_match_audit_id)
        counts["matches_deleted"] = _delete_post_baseline_matches(conn, baseline_max_match_id)
        deleted_classifications, restored_classifications = _reconcile_classifications(conn, classifications_baseline)
        counts["classifications_deleted"] = deleted_classifications
        counts["classifications_restored"] = restored_classifications
        counts["categories_deleted"] = _delete_post_baseline_categories(conn, baseline_max_category_id, run_id)
        counts["categories_restored"] = _restore_categories(conn, categories_baseline, baseline_max_category_id)
    return counts


def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    if len(sys.argv) != 4:
        print(
            "usage: dast_cleanup.py <baseline_json_path> <run_id> <summary_json_path>",
            file=sys.stderr,
        )
        return 2

    baseline_path = pathlib.Path(sys.argv[1])
    run_id = sys.argv[2]
    summary_path = pathlib.Path(sys.argv[3])

    summary: dict[str, Any] = {
        "status": "unknown",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "run_id": run_id,
        "baseline_path": str(baseline_path),
        "counts": {},
        "errors": [],
    }

    if not baseline_path.exists():
        return _skip_with_error(summary, summary_path, f"baseline file not found: {baseline_path}")

    baseline = _load_baseline(baseline_path)
    if baseline.get("status") != "captured":
        return _skip_with_error(summary, summary_path, f"baseline status is {baseline.get('status')!r}; nothing to restore")

    try:
        from teller.teller_db import get_engine
        from teller.teller_db_profile import resolve_profile
    except Exception as exc:
        return _skip_with_error(summary, summary_path, f"db_import_failed: {exc}")

    current_profile = resolve_profile()
    refusal_message = _profile_refusal_message(baseline.get("profile_name"), current_profile.name)
    if refusal_message:
        return _refuse_with_error(summary, summary_path, refusal_message)

    baseline_max_category_id = int(baseline.get("baseline_max_category_id", 0))
    baseline_max_match_id = int(baseline.get("baseline_max_match_id", 0))
    baseline_max_match_audit_id = int(baseline.get("baseline_max_match_audit_id", 0))

    matches_baseline = baseline.get("matches", []) or []
    classifications_baseline = baseline.get("classifications", []) or []
    categories_baseline = baseline.get("categories", []) or []

    try:
        counts = _run_cleanup_transaction(
            get_engine(),
            matches_baseline=matches_baseline,
            classifications_baseline=classifications_baseline,
            categories_baseline=categories_baseline,
            baseline_max_match_id=baseline_max_match_id,
            baseline_max_match_audit_id=baseline_max_match_audit_id,
            baseline_max_category_id=baseline_max_category_id,
            run_id=run_id,
        )
        summary["status"] = "applied"
        summary["counts"] = counts
    except Exception as exc:
        summary["status"] = "failed"
        summary["errors"].append(f"cleanup_exception: {exc!r}")
        return _emit_summary(summary_path, summary, {"status": summary["status"], "errors": summary["errors"]}, 1)

    return _emit_summary(
        summary_path,
        summary,
        {
            "status": summary["status"],
            "run_id": run_id,
            "counts": counts,
            "summary": str(summary_path),
        },
        0,
    )


if __name__ == "__main__":
    raise SystemExit(main())
