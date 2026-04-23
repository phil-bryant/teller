#! /usr/bin/env python3
import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Dict, List
import requests
import structlog
from dotenv import load_dotenv
from teller.teller_object import TellerObject
from teller.teller_account import TellerAccount
from teller.teller_account_identities import TellerAccountIdentities  # noqa: F401 — registers class with SQLAlchemy mapper
from teller.teller_identity import TellerIdentity
from teller.teller_transaction import TellerTransaction

log = structlog.get_logger()
TELLER_DIR = Path.home() / ".teller"

class TellerAPIError(Exception):
    def __init__(self, message: str, code: str = "", status_code: int = 0):
        super().__init__(message)
        self.message, self.code, self.status_code = message, code, status_code

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"

    def __init__(self, auth_token: str = "", enrollment_id: str = ""):
        load_dotenv(Path.home() / ".env")
        self._auth_token = auth_token
        self._enrollment_id = enrollment_id
        self._load_auth()
        TellerObject.set_api_client(self)

    def _load_auth(self):
        #R005: Load auth token and TLS cert/key from ~/.teller (or explicit auth token override).
        token = self._auth_token or json.loads((TELLER_DIR / "auth_token.json").read_text())["current"]
        self.kwargs = {
            'auth': (token, ""),
            'cert': (str(TELLER_DIR / "certificate.pem"), str(TELLER_DIR / "private_key.pem")),
            'headers': {"Accept": "application/json", "Content-Type": "application/json"},
            'verify': True
        }

    def _parse_error(self, response) -> tuple:
        try:
            err = response.json().get("error", {})
            code, message = err.get("code", ""), err.get("message", response.text)
        except ValueError:
            code, message = "", response.text
        return code, message

    def _repair_enrollment(self) -> bool:
        #R010: Attempt local Teller Connect repair for disconnected enrollments.
        enrollment_id_file = TELLER_DIR / "enrollment_id.txt"
        enrollment_id = self._enrollment_id or (enrollment_id_file.read_text().strip() if enrollment_id_file.is_file() else "")
        repaired = False
        if enrollment_id:
            try:
                import time, threading, webbrowser
                from http.server import ThreadingHTTPServer
                from teller_connect_token_server import (
                    APP_ID_FILE,
                    AUTH_TOKEN_FILE,
                    ENROLLMENT_ID_FILE,
                    CaptureState,
                    Handler,
                )
                state = CaptureState(
                    APP_ID_FILE.read_text(encoding="utf-8").strip(),
                    "development",
                    enrollment_id,
                    AUTH_TOKEN_FILE,
                    ENROLLMENT_ID_FILE,
                    "capture",
                    [],
                )
                server = ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
                server.capture_state = state
                print(f"Enrollment disconnected — repairing {enrollment_id} via Teller Connect\n"
                      f"Complete the challenge in your browser at http://localhost:8080")
                threading.Thread(target=server.serve_forever, daemon=True).start()
                webbrowser.open("http://localhost:8080")
                try:
                    while not state.token_saved:
                        time.sleep(0.25)
                    repaired = True
                    self._load_auth()
                    print("Enrollment repaired. Resuming...")
                except KeyboardInterrupt:
                    print("\nRepair cancelled.")
                server.shutdown()
                server.server_close()
            except (ImportError, OSError) as exc:
                log.warning("Auto-repair failed", error=str(exc))
        else:
            log.warning("Cannot auto-repair: no enrollment ID", path=str(enrollment_id_file))
        return repaired

    def get(self, url: str, params: Dict = None) -> dict:
        log.info("Connecting to Teller API", url=url, params=params, auth_token=self.kwargs['auth'][0][:5])
        response = requests.get(url, params=params, **self.kwargs)
        code = self._parse_error(response)[0] if response.status_code != 200 else ""
        #R010: Retry once after successful enrollment repair.
        if code.startswith("enrollment.disconnected") and self._repair_enrollment():
            log.info("Retrying after enrollment repair", url=url)
            response = requests.get(url, params=params, **self.kwargs)
        if response.status_code != 200:
            code, message = self._parse_error(response)
            raise TellerAPIError(message=message, code=code, status_code=response.status_code)
        return response.json()


def _fetch_all_transactions(client, txn_url):
    #R015: Fetch complete transaction history by paging with from_id cursor.
    all_txns, page = [], client.get(txn_url)
    while page:
        all_txns.extend(page)
        last_id = page[-1]["id"]
        log.info("Fetched transaction page", count=len(page), total=len(all_txns), oldest=page[-1]["date"], last_id=last_id)
        page = client.get(txn_url, {"from_id": last_id})
        log.info("Pagination response", from_id=last_id, returned=len(page) if isinstance(page, list) else type(page).__name__)
    log.info("Pagination complete", total=len(all_txns))
    return all_txns

def _read_token_file(path: Path) -> str:
    token = ""
    if path.is_file():
        token = json.loads(path.read_text()).get("current", "")
    return token

def _read_text_file(path: Path) -> str:
    value = ""
    if path.is_file():
        value = path.read_text().strip()
    return value

def _load_metadata_contexts() -> List[dict]:
    metadata_path = TELLER_DIR / "enrollments.json"
    contexts = []
    if metadata_path.is_file():
        payload = json.loads(metadata_path.read_text())
        if isinstance(payload, list):
            for row in payload:
                if isinstance(row, dict):
                    contexts.append({
                        "enrollment_id": row.get("enrollment_id", ""),
                        "token": row.get("token", ""),
                        "institution_id": row.get("institution_id", ""),
                    })
    return contexts

def _load_suffix_contexts() -> List[dict]:
    contexts = []
    for token_file in sorted(TELLER_DIR.glob("auth_token_*.json")):
        suffix = token_file.name[11:-5]
        contexts.append({
            "enrollment_id": _read_text_file(TELLER_DIR / f"enrollment_id_{suffix}.txt"),
            "token": _read_token_file(token_file),
            "institution_id": suffix,
        })
    return contexts

def _infer_enrollment_ids_from_db(institution_id: str) -> List[str]:
    inferred = []
    try:
        from sqlalchemy import text
        from teller.teller_db import get_session
        session = get_session()
        try:
            rows = session.execute(text("""
                SELECT DISTINCT enrollment_id
                FROM teller.account
                WHERE institution_id = :institution_id
                ORDER BY enrollment_id
            """), {"institution_id": institution_id}).fetchall()
            inferred = [row[0] for row in rows if row and row[0]]
        finally:
            session.close()
    except Exception as exc:
        log.info("Enrollment inference skipped", institution_id=institution_id, error=str(exc))
    return inferred

def _dedupe_contexts(contexts: List[dict]) -> List[dict]:
    deduped = {}
    for row in contexts:
        enrollment_id = row.get("enrollment_id", "")
        institution_id = row.get("institution_id", "")
        token = row.get("token", "")
        key = enrollment_id or f"{institution_id}:{token[:12]}"
        if key:
            deduped[key] = {"enrollment_id": enrollment_id, "token": token, "institution_id": institution_id}
    return list(deduped.values())

def _fetch_context_data(client: TellerAPIClient, institution_id: str) -> tuple:
    raw_identities = client.get(f"{client.BASE_URL}/identity")
    filtered_identities = [item for item in raw_identities if not institution_id or
                           item["account"]["institution"]["id"] == institution_id]
    raw_transactions_by_account, raw_balances_by_account = {}, {}
    for item in filtered_identities:
        account_data = item["account"]
        account = TellerAccount(account_data)
        print(f"Account: {account.name} ({account.id}) — {account.institution.name}")
        raw_txns = _fetch_all_transactions(client, account.links.transactions)
        raw_transactions_by_account[account_data["id"]] = raw_txns
        print(json.dumps(raw_txns, indent=2))
        for td in raw_txns:
            txn = TellerTransaction(td)
            print(f"  {txn.date} {txn.amount:>10} {txn.description}")
        if account.links.balances:
            raw_bal = client.get(account.links.balances)
            raw_balances_by_account[account_data["id"]] = raw_bal
            print(f"  Balances: ledger={raw_bal.get('ledger')} available={raw_bal.get('available')}")
        for owner_data in item["owners"]:
            owner = TellerIdentity(owner_data)
            print(f"  Owner: {owner.type.value} — {', '.join(n.data for n in owner.names)}")
    return filtered_identities, raw_transactions_by_account, raw_balances_by_account

def _build_enrollment_contexts(institution_id: str) -> List[dict]:
    #R020: Merge default/metadata/suffix enrollment contexts, then dedupe and optionally scope by institution.
    contexts = [{
        "enrollment_id": _read_text_file(TELLER_DIR / "enrollment_id.txt"),
        "token": _read_token_file(TELLER_DIR / "auth_token.json"),
        "institution_id": "",
    }]
    contexts.extend(_load_metadata_contexts())
    contexts.extend(_load_suffix_contexts())
    contexts = _dedupe_contexts(contexts)
    if institution_id:
        matched = [row for row in contexts if row.get("institution_id") == institution_id]
        if not matched:
            inferred = _infer_enrollment_ids_from_db(institution_id)
            matched = [{"enrollment_id": enrollment_id, "token": "", "institution_id": institution_id}
                       for enrollment_id in inferred]
        contexts = matched if matched else contexts
    contexts = contexts if contexts else [{"enrollment_id": "", "token": "", "institution_id": ""}]
    return contexts

def main():
    #R001: Parse CLI flags and configure runtime log level.
    parser = argparse.ArgumentParser(description='Teller API Client')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--dry-run', action='store_true', help='Fetch and print Teller data without persisting to DB')
    parser.add_argument('--institution_id', type=str)
    args = parser.parse_args()
    structlog.configure(wrapper_class=structlog.make_filtering_bound_logger(logging.DEBUG if args.debug else logging.INFO))
    try:
        contexts = _build_enrollment_contexts(args.institution_id or "")
        raw_identities, raw_transactions_by_account, raw_balances_by_account = [], {}, {}
        errors = []
        for context in contexts:
            try:
                client = TellerAPIClient(auth_token=context["token"], enrollment_id=context["enrollment_id"])
                ids, tx_by_account, bals_by_account = _fetch_context_data(client, args.institution_id)
                print(json.dumps(ids, indent=2))
                raw_identities.extend(ids)
                raw_transactions_by_account.update(tx_by_account)
                raw_balances_by_account.update(bals_by_account)
            except TellerAPIError as exc:
                errors.append(
                    {"institution_id": context.get("institution_id", ""), "enrollment_id": context.get("enrollment_id", ""),
                     "status_code": exc.status_code, "message": exc.message, "code": exc.code}
                )
        if not raw_identities and errors:
            first = errors[0]
            raise TellerAPIError(message=first["message"], code=first["code"], status_code=first["status_code"])
        if errors:
            for err in errors:
                print(f"Enrollment failed: institution_id={err['institution_id']} enrollment_id={err['enrollment_id']}")
                print(f"  status={err['status_code']} code={err['code']} message={err['message']}")
        #R025: Persist fetched Teller data unless running in dry-run mode.
        if not args.dry_run:
            from teller.teller_db import get_session
            from teller.teller_persist import persist_all
            session = get_session()
            try:
                #R030 #R035: Transaction canonicalization and stale-graph cleanup are handled inside persist_all.
                persist_all(session, raw_identities, raw_transactions_by_account, raw_balances_by_account)
                print("Persisted to database.")
            except Exception as exc:
                session.rollback()
                print(f"Persistence failed: {exc}")
                raise
            finally:
                session.close()
        else:
            print("Dry run complete. No database changes were made.")
    except TellerAPIError as exc:
        print(f"Teller API request failed ({exc.status_code}): {exc.message}")
        if exc.code:
            print(f"Error code: {exc.code}")
        if exc.code.startswith("enrollment.disconnected"):
            print("Auto-repair failed. Run ./08_capture_teller_token.sh to repair the enrollment manually.")
        sys.exit(1)

if __name__ == "__main__":
    main()