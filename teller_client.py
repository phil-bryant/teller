#! /usr/bin/env python3
import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Dict
import requests
import structlog
from dotenv import load_dotenv
from teller_object import TellerObject
from teller_account import TellerAccount
from teller_account_identities import TellerAccountIdentities  # noqa: F401 — registers class with SQLAlchemy mapper
from teller_identity import TellerIdentity
from teller_transaction import TellerTransaction

log = structlog.get_logger()
TELLER_DIR = Path.home() / ".teller"

class TellerAPIError(Exception):
    def __init__(self, message: str, code: str = "", status_code: int = 0):
        super().__init__(message)
        self.message, self.code, self.status_code = message, code, status_code

class TellerAPIClient:
    BASE_URL = "https://api.teller.io"

    def __init__(self):
        load_dotenv(Path.home() / ".env")
        self._load_auth()
        TellerObject.set_api_client(self)

    def _load_auth(self):
        self.kwargs = {
            'auth': (json.loads((TELLER_DIR / "auth_token.json").read_text())["current"], ""),
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
        enrollment_id_file = TELLER_DIR / "enrollment_id.txt"
        enrollment_id = enrollment_id_file.read_text().strip() if enrollment_id_file.is_file() else ""
        repaired = False
        if enrollment_id:
            try:
                import time, threading, webbrowser
                from http.server import ThreadingHTTPServer
                from teller_connect_token_server import CaptureState, Handler, APP_ID_FILE
                state = CaptureState(APP_ID_FILE.read_text(encoding="utf-8").strip(), "development", enrollment_id)
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
        log.info("Connecting to Teller API", url=url, cert=self.kwargs['cert'], auth_token=self.kwargs['auth'][0][:5])
        response = requests.get(url, params=params, **self.kwargs)
        code = self._parse_error(response)[0] if response.status_code != 200 else ""
        if code.startswith("enrollment.disconnected") and self._repair_enrollment():
            log.info("Retrying after enrollment repair", url=url)
            response = requests.get(url, params=params, **self.kwargs)
        if response.status_code != 200:
            code, message = self._parse_error(response)
            raise TellerAPIError(message=message, code=code, status_code=response.status_code)
        return response.json()


def main():
    parser = argparse.ArgumentParser(description='Teller API Client')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--persist', action='store_true')
    args = parser.parse_args()
    structlog.configure(wrapper_class=structlog.make_filtering_bound_logger(logging.DEBUG if args.debug else logging.INFO))
    try:
        client = TellerAPIClient()
        raw_identities = client.get(f"{client.BASE_URL}/identity")
        print(json.dumps(raw_identities, indent=2))
        raw_transactions_by_account = {}
        for item in raw_identities:
            account_data = item["account"]
            account = TellerAccount(account_data)
            ## we cannot call account.get_details() yet because we first have to go through the microdeposit verification flow.
            print(f"Account: {account.name} ({account.id}) — {account.institution.name}")
            txn_url = account.links.transactions
            raw_txns = client.get(txn_url)
            raw_transactions_by_account[account_data["id"]] = raw_txns
            print(json.dumps(raw_txns, indent=2))
            for td in raw_txns:
                txn = TellerTransaction(td)
                print(f"  {txn.date} {txn.amount:>10} {txn.description}")
            for owner_data in item["owners"]:
                owner = TellerIdentity(owner_data)
                print(f"  Owner: {owner.type.value} — {', '.join(n.data for n in owner.names)}")
        if args.persist:
            from teller_db import get_session
            from teller_persist import persist_all
            session = get_session()
            try:
                persist_all(session, raw_identities, raw_transactions_by_account)
                print("Persisted to database.")
            except Exception as exc:
                session.rollback()
                print(f"Persistence failed: {exc}")
                raise
            finally:
                session.close()
    except TellerAPIError as exc:
        print(f"Teller API request failed ({exc.status_code}): {exc.message}")
        if exc.code:
            print(f"Error code: {exc.code}")
        if exc.code.startswith("enrollment.disconnected"):
            print("Auto-repair failed. Run ./06_capture_teller_token.sh to repair the enrollment manually.")
        sys.exit(1)

if __name__ == "__main__":
    main()