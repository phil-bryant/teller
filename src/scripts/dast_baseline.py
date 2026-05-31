#!/usr/bin/env python3
#R001: Capture baseline maxima and mutable-row snapshots for DAST-affected tables.
#R005: Degrade safely to skipped payload when DB dependencies are unavailable.
#R010: Emit concise JSON summary output after writing baseline artifacts.
"""Capture a pre-DAST snapshot of every database row tests/t12_run_dynamic_security_tests.sh may touch.

Writes a JSON document containing:
    - profile_name: active TELLER_DB_PROFILE for safety matching at cleanup time.
    - baseline_max_category_id / baseline_max_match_id / baseline_max_match_audit_id:
      watermarks used to delete rows inserted during the run.
    - categories: full mutable-field snapshot of every existing ``nys_snw_category``
      row (so PUTs to existing categories can be restored). Seed rows are included
      for completeness even though triggers make them immutable.
    - matches: every existing ``transaction_email_match`` row's mutable fields
      (state, selected_by, selected_at, email_message_id, active, updated_at,
      moved_to_matchy_at).
    - classifications: every existing ``transaction_nys_snw_category`` row
      (transaction_id, nys_snw_category_id, type) so PUT classifications can be
      restored or removed.

Usage:
    dast_baseline.py <output_json_path>
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
from datetime import datetime, timezone
from typing import Any


def _iso(value: Any) -> Any:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()
    return value


def _serialize_row(row, columns: list[str]) -> dict[str, Any]:
    return {col: _iso(row[idx]) for idx, col in enumerate(columns)}


def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    if len(sys.argv) != 2:
        print("usage: dast_baseline.py <output_json_path>", file=sys.stderr)
        return 2

    output_path = pathlib.Path(sys.argv[1])

    try:
        from teller.teller_db import get_engine
        from teller.teller_db_profile import resolve_profile
    except Exception as exc:
        print(f"dast_baseline: database dependencies unavailable: {exc}", file=sys.stderr)
        payload = {
            "status": "skipped",
            "reason": f"db_import_failed: {exc}",
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        return 0

    profile = resolve_profile()
    engine = get_engine()

    payload: dict[str, Any] = {
        "status": "captured",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "profile_name": profile.name,
        "profile_host": profile.host,
        "profile_dbname": profile.dbname,
    }

    with engine.connect() as conn:
        payload["baseline_max_category_id"] = int(
            conn.exec_driver_sql(
                "SELECT COALESCE(MAX(nys_snw_category_id), 0) FROM teller.nys_snw_category"
            ).scalar_one()
        )
        payload["baseline_max_match_id"] = int(
            conn.exec_driver_sql(
                "SELECT COALESCE(MAX(match_id), 0) FROM teller.transaction_email_match"
            ).scalar_one()
        )
        payload["baseline_max_match_audit_id"] = int(
            conn.exec_driver_sql(
                "SELECT COALESCE(MAX(match_audit_id), 0) FROM teller.transaction_email_match_audit"
            ).scalar_one()
        )

        category_columns = [
            "nys_snw_category_id",
            "level_1",
            "level_1_name",
            "level_2",
            "level_2_name",
            "level_3",
            "level_4",
            "categorization",
            "applicability",
            "is_seed",
        ]
        category_rows = conn.exec_driver_sql(
            f"SELECT {', '.join(category_columns)} FROM teller.nys_snw_category"
        ).fetchall()
        payload["categories"] = [_serialize_row(row, category_columns) for row in category_rows]

        match_columns = [
            "match_id",
            "transaction_id",
            "email_message_id",
            "state",
            "ai_confidence",
            "selected_by",
            "selected_at",
            "moved_to_matchy_at",
            "active",
            "updated_at",
        ]
        match_rows = conn.exec_driver_sql(
            f"SELECT {', '.join(match_columns)} FROM teller.transaction_email_match"
        ).fetchall()
        serialized_matches = []
        for row in match_rows:
            row_dict = _serialize_row(row, match_columns)
            if row_dict.get("ai_confidence") is not None:
                row_dict["ai_confidence"] = str(row_dict["ai_confidence"])
            serialized_matches.append(row_dict)
        payload["matches"] = serialized_matches

        classification_columns = ["transaction_id", "nys_snw_category_id", "type"]
        classification_rows = conn.exec_driver_sql(
            f"SELECT {', '.join(classification_columns)} FROM teller.transaction_nys_snw_category"
        ).fetchall()
        payload["classifications"] = [
            _serialize_row(row, classification_columns) for row in classification_rows
        ]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, default=str)
        fh.write("\n")

    print(
        json.dumps(
            {
                "status": payload["status"],
                "profile": payload.get("profile_name"),
                "baseline_max_category_id": payload.get("baseline_max_category_id"),
                "baseline_max_match_id": payload.get("baseline_max_match_id"),
                "baseline_max_match_audit_id": payload.get("baseline_max_match_audit_id"),
                "categories": len(payload.get("categories", [])),
                "matches": len(payload.get("matches", [])),
                "classifications": len(payload.get("classifications", [])),
                "output": str(output_path),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
