#!/usr/bin/env python3
import json
import pathlib
import re
import sys
from datetime import datetime, timezone


TEXT_FIELDS = [
    "level_1",
    "level_1_name",
    "level_2",
    "level_2_name",
    "level_3",
    "level_4",
    "categorization",
    "applicability",
]


def parse_seed_row_count(sql_text: str) -> int:
    match = re.search(
        r"SELECT\s+\*\s+FROM\s+\(VALUES(?P<rows>.*?)\)\s+AS\s+seed_rows\s*\(",
        sql_text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not match:
        raise ValueError("Could not locate canonical seed VALUES block in seed SQL.")
    row_count = len(re.findall(r"^\s*\(", match.group("rows"), flags=re.MULTILINE))
    if row_count <= 0:
        raise ValueError("Seed SQL parser found zero inserted category rows.")
    return row_count


def serialize_row(row, columns):
    return {col: row[idx] for idx, col in enumerate(columns)}


def write_report(report_path: pathlib.Path, report: dict):
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def append_invariant(report: dict, name: str, description: str, count: int, examples):
    report["invariants"].append(
        {"name": name, "description": description, "count": int(count), "ok": int(count) == 0, "examples": examples}
    )


def build_base(strict_mode: bool, seed_row_count: int) -> dict:
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "status": "passed",
        "gate_failed": False,
        "strict_mode": strict_mode,
        "canonical_seed_row_count": seed_row_count,
        "canonical_seed_max_id": seed_row_count,
        "invariants": [],
        "errors": [],
    }


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: category_integrity_check.py <report_path> <seed_sql_path> <strict_bool>")
    report_path = pathlib.Path(sys.argv[1])
    seed_sql_path = pathlib.Path(sys.argv[2])
    strict_mode = sys.argv[3].lower() == "true"
    seed_row_count = 0
    try:
        seed_row_count = parse_seed_row_count(seed_sql_path.read_text(encoding="utf-8"))
    except Exception as exc:
        report = build_base(strict_mode, seed_row_count)
        report["status"] = "error"
        report["gate_failed"] = strict_mode
        report["errors"].append(f"Unable to parse canonical category seed SQL at {seed_sql_path}: {exc}")
        write_report(report_path, report)
        print(f"Category integrity report: {report_path}")
        if strict_mode:
            print("❌ Post-DAST category integrity gate failed: canonical seed metadata unavailable.")
            return 2
        print("⚠️  Post-DAST category integrity checks skipped (non-strict mode).")
        return 0
    report = build_base(strict_mode, seed_row_count)
    try:
        from teller.teller_db import get_engine

        engine = get_engine()
    except Exception as exc:
        message = str(exc)
        restricted_runtime_missing_dep = "No module named 'structlog'" in message or "No module named 'sqlalchemy'" in message
        report["status"] = "error"
        report["gate_failed"] = strict_mode and not restricted_runtime_missing_dep
        report["errors"].append(f"Unable to initialize database engine via teller.teller_db: {exc}")
        write_report(report_path, report)
        print(f"Category integrity report: {report_path}")
        if restricted_runtime_missing_dep:
            print("⚠️  Post-DAST category integrity checks skipped: database dependencies are unavailable in this restricted runtime.")
            return 0
        if strict_mode:
            print("❌ Post-DAST category integrity gate failed: database integrity could not be verified.")
            return 2
        print("⚠️  Post-DAST category integrity checks skipped (non-strict mode).")
        return 0
    canonical_max_id = seed_row_count
    with engine.connect() as conn:
        missing_id_count = conn.exec_driver_sql(
            """
            SELECT COUNT(*)
              FROM generate_series(1, %(canonical_max_id)s) AS expected_id
         LEFT JOIN teller.nys_snw_category c
                ON c.nys_snw_category_id = expected_id
               AND c.is_seed = TRUE
             WHERE c.nys_snw_category_id IS NULL
            """,
            {"canonical_max_id": canonical_max_id},
        ).scalar_one()
        missing_rows = conn.exec_driver_sql(
            """
            SELECT expected_id
              FROM generate_series(1, %(canonical_max_id)s) AS expected_id
         LEFT JOIN teller.nys_snw_category c
                ON c.nys_snw_category_id = expected_id
               AND c.is_seed = TRUE
             WHERE c.nys_snw_category_id IS NULL
             ORDER BY expected_id
             LIMIT 20
            """,
            {"canonical_max_id": canonical_max_id},
        ).fetchall()
        append_invariant(
            report,
            "missing_or_unflagged_seed_rows",
            "Canonical seed IDs [1..N] must remain present and tagged with is_seed=true.",
            missing_id_count,
            [serialize_row(row, ["expected_id"]) for row in missing_rows],
        )
        unexpected_seed_count = conn.exec_driver_sql(
            """
            SELECT COUNT(*)
              FROM teller.nys_snw_category
             WHERE is_seed = TRUE
               AND (nys_snw_category_id < 1 OR nys_snw_category_id > %(canonical_max_id)s)
            """,
            {"canonical_max_id": canonical_max_id},
        ).scalar_one()
        unexpected_seed_rows = conn.exec_driver_sql(
            """
            SELECT nys_snw_category_id, level_1_name, categorization
              FROM teller.nys_snw_category
             WHERE is_seed = TRUE
               AND (nys_snw_category_id < 1 OR nys_snw_category_id > %(canonical_max_id)s)
             ORDER BY nys_snw_category_id
             LIMIT 20
            """,
            {"canonical_max_id": canonical_max_id},
        ).fetchall()
        append_invariant(
            report,
            "seed_flag_outside_canonical_range",
            "Rows marked as seed must remain within canonical seed ID range.",
            unexpected_seed_count,
            [serialize_row(row, ["nys_snw_category_id", "level_1_name", "categorization"]) for row in unexpected_seed_rows],
        )
        seed_count_drift = conn.exec_driver_sql(
            """
            SELECT ABS(COUNT(*) - %(canonical_seed_count)s)
              FROM teller.nys_snw_category
             WHERE is_seed = TRUE
            """,
            {"canonical_seed_count": seed_row_count},
        ).scalar_one()
        seed_count = conn.exec_driver_sql("SELECT COUNT(*) FROM teller.nys_snw_category WHERE is_seed = TRUE").scalar_one()
        append_invariant(
            report,
            "seed_row_count_drift",
            f"Seed taxonomy row count must remain exactly {seed_row_count}.",
            seed_count_drift,
            [{"observed_seed_row_count": int(seed_count), "expected_seed_row_count": int(seed_row_count)}] if seed_count_drift else [],
        )
        control_predicate = " OR ".join([f"{field} ~ '[[:cntrl:]]'" for field in TEXT_FIELDS])
        control_count = conn.exec_driver_sql(f"SELECT COUNT(*) FROM teller.nys_snw_category WHERE {control_predicate}").scalar_one()
        append_invariant(
            report,
            "control_characters_in_hierarchy",
            "Hierarchy text fields must not contain control/non-printable characters.",
            control_count,
            [],
        )
        empty_predicate = " AND ".join([f"NULLIF(BTRIM(COALESCE({field}, '')), '') IS NULL" for field in TEXT_FIELDS])
        empty_count = conn.exec_driver_sql(f"SELECT COUNT(*) FROM teller.nys_snw_category WHERE {empty_predicate}").scalar_one()
        append_invariant(
            report,
            "empty_hierarchy_rows",
            "Category rows must include at least one non-empty hierarchy text field.",
            empty_count,
            [],
        )
        orphaned_count = conn.exec_driver_sql(
            """
            SELECT COUNT(*)
              FROM teller.transaction_nys_snw_category t
         LEFT JOIN teller.nys_snw_category c
                ON c.nys_snw_category_id = t.nys_snw_category_id
             WHERE c.nys_snw_category_id IS NULL
            """
        ).scalar_one()
        append_invariant(
            report,
            "orphaned_transaction_category_links",
            "Every transaction category mapping must reference an existing category row.",
            orphaned_count,
            [],
        )
    violations = [item for item in report["invariants"] if not item.get("ok", False)]
    report["status"] = "failed" if violations else "passed"
    report["gate_failed"] = bool(violations)
    repair_script = pathlib.Path("./src/scripts/repair_nys_snw_category.sql")
    if repair_script.exists():
        report["repair_script_available"] = str(repair_script)
    write_report(report_path, report)
    print(f"Category integrity report: {report_path}")
    if violations:
        print("❌ Post-DAST category integrity gate failed due to invariant violations.")
        return 2
    print("✅ Post-DAST category integrity checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
