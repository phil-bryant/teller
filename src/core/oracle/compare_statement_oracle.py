#!/usr/bin/env python3
"""Statement parsing parity oracle: 08_backfill_bank_statements (Python) vs
tellercore::statement (C++).

OCR itself is nondeterministic, so parity runs at the parser boundary: both
implementations consume identical OCR observation fixtures, reconstruct page
text, parse the activity tables, and must produce identical transaction lists
(date/amount/description/type), deterministic transaction ids, statement
period, and summary totals. The Python side drives the retired 08 functions
directly; the C++ side is the teller_oracle_runner replay-statements output.

Usage:
  compare_statement_oracle.py --runner <teller_oracle_runner> \
      [--scenarios <statement_scenarios.json>]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
BACKFILL_SCRIPT = REPO_ROOT / "08_backfill_bank_statements.py"

# Allowlisted, explained Python divergences (scenario name -> reason). Empty
# today; populate only with a justified Python-specific artifact.
KNOWN_DIVERGENCES: dict[str, str] = {}


#R001: Traceability for function `load_backfill_module`.
def load_backfill_module():
    spec = importlib.util.spec_from_file_location("teller_backfill_ref", BACKFILL_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {BACKFILL_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


#R001: Traceability for function `python_scenario`.
def python_scenario(module, scenario: dict) -> dict:
    account_id = scenario.get("account_id", "acc_test")
    page_texts = []
    for page in scenario["pages"]:
        points = [(o["y"], o["x"], o["text"]) for o in page["observations"]]
        page_texts.append("\n".join(module.reconstruct_lines(points)))

    if "year" in scenario and "month" in scenario:
        year, month = scenario["year"], scenario["month"]
    else:
        year, month = module.extract_statement_year(page_texts)

    txns = module.parse_transactions(page_texts, year, month)
    seen: dict[tuple, int] = {}
    transactions = []
    for txn in txns:
        key = (txn["date"], txn["amount"], txn["description"])
        seen[key] = seen.get(key, 0) + 1
        transactions.append(
            {
                "id": module.make_txn_id(
                    account_id, txn["date"], txn["amount"], txn["description"], seen[key]
                ),
                "date": txn["date"],
                "amount": txn["amount"],
                "description": txn["description"],
                "type": txn["type"],
            }
        )

    dep_count, dep_total, wd_count, wd_total = module.extract_summary(page_texts)
    summary = {
        "deposit_count": dep_count,
        "deposit_total": str(dep_total) if dep_total is not None else None,
        "withdrawal_count": wd_count,
        "withdrawal_total": str(wd_total) if wd_total is not None else None,
    }
    return {
        "name": scenario["name"],
        "year": year,
        "month": month,
        "transactions": transactions,
        "summary": summary,
    }


#R001: Traceability for function `run_python_side`.
def run_python_side(module, scenarios: list) -> dict:
    return {s["name"]: python_scenario(module, s) for s in scenarios}


#R001: Traceability for function `run_cpp_side`.
def run_cpp_side(runner: str, scenarios_path: str) -> dict:
    out = subprocess.run(
        [runner, "replay-statements", "--scenarios", scenarios_path],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    doc = json.loads(out)
    return {s["name"]: s for s in doc["scenarios"]}


#R001: Traceability for function `main`.
def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="teller statement parsing parity oracle")
    parser.add_argument("--runner", required=True)
    parser.add_argument("--scenarios", default=str(here / "statement_scenarios.json"))
    args = parser.parse_args()

    scenarios_doc = json.loads(Path(args.scenarios).read_text())
    scenarios = scenarios_doc["scenarios"]

    module = load_backfill_module()
    cpp = run_cpp_side(args.runner, args.scenarios)
    py = run_python_side(module, scenarios)

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
        print(f"  python: {json.dumps(py_snap)[:600]}")
        print(f"  c++:    {json.dumps(cpp_snap)[:600]}")

    total = len(scenarios)
    print(
        f"\nstatement parity: {total} scenarios, {failures} failures, "
        f"{len(KNOWN_DIVERGENCES)} known divergences"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
