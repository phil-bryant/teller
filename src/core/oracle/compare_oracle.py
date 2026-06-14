#!/usr/bin/env python3
"""Persist parity oracle: teller_persist (Python) vs tellercore::persist (C++).

For each scenario in scenarios.json, both implementations ingest the same Teller
API payloads into a fresh SQLCipher database and must leave identical normalized
teller.* state. The Python side drives teller_persist directly; the C++ side is
the teller_oracle_runner replay (record) output. Snapshots drop bookkeeping
timestamps; money is integer cents on both sqlite sides.

Usage:
  compare_oracle.py --runner <teller_oracle_runner> --scenarios <scenarios.json> \
      --ddl <create_database.sql> [--key <key>]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from pysqlcipher3 import dbapi2 as sqlcipher  # noqa: E402

# (table, snapshot query) -- must match oracle_runner.cpp kSnapshotTables order.
SNAPSHOT_TABLES = [
    ("institution", "SELECT * FROM institution ORDER BY institution_id"),
    ("account_links", "SELECT * FROM account_links ORDER BY account_links_id"),
    ("account", "SELECT * FROM account ORDER BY account_id"),
    ("identity", "SELECT * FROM identity ORDER BY identity_id"),
    ("identity_name", "SELECT * FROM identity_name ORDER BY identity_name_id"),
    ("identity_email", "SELECT * FROM identity_email ORDER BY identity_email_id"),
    ("identity_phone_number", "SELECT * FROM identity_phone_number ORDER BY identity_phone_number_id"),
    ("identity_address_data", "SELECT * FROM identity_address_data ORDER BY identity_address_data_id"),
    ("identity_address", "SELECT * FROM identity_address ORDER BY identity_address_id"),
    ("account_identities", "SELECT * FROM account_identities ORDER BY account_identities_id"),
    ("account_balances_links", "SELECT * FROM account_balances_links ORDER BY account_balances_links_id"),
    ("account_balances", "SELECT * FROM account_balances ORDER BY account_balances_id"),
    ("transaction_type", "SELECT * FROM transaction_type ORDER BY transaction_type_id"),
    (
        "transaction_details_counterparty",
        "SELECT * FROM transaction_details_counterparty ORDER BY transaction_details_counterparty_id",
    ),
    ("transaction_details", "SELECT * FROM transaction_details ORDER BY transaction_details_id"),
    ("transaction_links", "SELECT * FROM transaction_links ORDER BY transaction_links_id"),
    ('transaction', 'SELECT * FROM "transaction" ORDER BY transaction_id'),
]
DROP_COLUMNS = {"created_at", "updated_at"}

# Allowlisted, explained Python-on-SQLite divergences (scenario name -> reason).
# Empty today; populate with a justification if a difference is provably a
# Python/pysqlcipher3 artifact rather than a C++ regression.
KNOWN_DIVERGENCES: dict[str, str] = {}


#R001: Traceability for function `python_snapshot`.
def python_snapshot(db_path: str, key: str) -> dict:
    conn = sqlcipher.connect(db_path)
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = '{key}'")
    snapshot: dict[str, list] = {}
    for table, snapshot_query in SNAPSHOT_TABLES:
        cur.execute(snapshot_query)
        columns = [d[0] for d in cur.description]
        rows = []
        for raw in cur.fetchall():
            row = {col: value for col, value in zip(columns, raw) if col not in DROP_COLUMNS}
            rows.append(row)
        snapshot[table] = rows
    cur.close()
    conn.close()
    return snapshot


#R001: Traceability for function `run_python_side`.
def run_python_side(scenarios: list, ddl_sql: str, key: str) -> dict:
    import teller.teller_db as teller_db
    from teller.teller_db_profile import reset_profile_cache
    from teller.teller_persist import persist_all

    results: dict[str, dict] = {}
    for scenario in scenarios:
        with tempfile.TemporaryDirectory(prefix="teller-oracle-py-") as tmp:
            db_path = os.path.join(tmp, "fixture.sqlite3")
            # Bootstrap the schema directly into the file (main schema).
            boot = sqlcipher.connect(db_path)
            boot_cur = boot.cursor()
            boot_cur.execute(f"PRAGMA key = '{key}'")
            boot_cur.executescript(ddl_sql)
            boot.commit()
            boot_cur.close()
            boot.close()

            os.environ["TELLER_DB_SQLITE_PATH"] = db_path
            os.environ["TELLER_DB_SQLCIPHER_KEY"] = key
            teller_db._engine = None
            reset_profile_cache()
            session = teller_db.get_session()
            try:
                for step in scenario["steps"]:
                    persist_all(
                        session,
                        step.get("identities", []),
                        step.get("transactions_by_account", {}),
                        step.get("balances_by_account", {}),
                    )
            finally:
                session.close()
                teller_db._engine = None
            results[scenario["name"]] = python_snapshot(db_path, key)
    return results


#R001: Traceability for function `run_cpp_side`.
def run_cpp_side(runner: str, scenarios_path: str, ddl_path: str, key: str) -> dict:
    with tempfile.NamedTemporaryFile("r", suffix=".json", delete=False) as out:
        record_path = out.name
    subprocess.run(
        [runner, "replay", "--scenarios", scenarios_path, "--ddl", ddl_path,
         "--record", record_path, "--key", key],
        check=True,
    )
    doc = json.loads(Path(record_path).read_text())
    os.unlink(record_path)
    return {s["name"]: s["snapshot"] for s in doc["scenarios"]}


#R001: Traceability for function `main`.
def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="teller persist parity oracle")
    parser.add_argument("--runner", required=True)
    parser.add_argument("--scenarios", default=str(here / "scenarios.json"))
    parser.add_argument("--ddl", default=str(REPO_ROOT / "src" / "sql" / "sqlite" / "create_database.sql"))
    parser.add_argument("--key", default="teller-oracle-key")
    args = parser.parse_args()

    scenarios_doc = json.loads(Path(args.scenarios).read_text())
    scenarios = scenarios_doc["scenarios"]
    ddl_sql = Path(args.ddl).read_text()

    cpp = run_cpp_side(args.runner, args.scenarios, args.ddl, args.key)
    py = run_python_side(scenarios, ddl_sql, args.key)

    failures = 0
    for scenario in scenarios:
        name = scenario["name"]
        # Re-roundtrip both through json so int/str/None types compare cleanly.
        cpp_snap = json.loads(json.dumps(cpp.get(name)))
        py_snap = json.loads(json.dumps(py.get(name)))
        if cpp_snap == py_snap:
            print(f"PASS {name}")
            continue
        if name in KNOWN_DIVERGENCES:
            print(f"KNOWN-DIVERGENCE {name}: {KNOWN_DIVERGENCES[name]}")
            continue
        failures += 1
        print(f"FAIL {name}")
        for table, _ in SNAPSHOT_TABLES:
            if cpp_snap.get(table) != py_snap.get(table):
                print(f"  table {table} differs")
                print(f"    python: {json.dumps(py_snap.get(table))[:400]}")
                print(f"    c++:    {json.dumps(cpp_snap.get(table))[:400]}")

    total = len(scenarios)
    print(f"\noracle parity: {total} scenarios, {failures} failures, "
          f"{len(KNOWN_DIVERGENCES)} known divergences")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
