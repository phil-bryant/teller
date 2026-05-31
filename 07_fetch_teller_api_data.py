#! /usr/bin/env python3
import argparse
import hashlib
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List

REPO_ROOT = Path(__file__).resolve().parent
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

import requests  # noqa: E402
import structlog  # noqa: E402
from dotenv import load_dotenv  # noqa: E402
from teller.teller_object import TellerObject  # noqa: E402
from teller.teller_account import TellerAccount  # noqa: E402
from teller.teller_account_identities import TellerAccountIdentities  # noqa: F401,E402 — registers class with SQLAlchemy mapper
from teller.teller_identity import TellerIdentity  # noqa: F401,E402
from teller.teller_transaction import TellerTransaction  # noqa: F401,E402

log = structlog.get_logger()
TELLER_DIR = Path.home() / ".teller"
REQUEST_TIMEOUT_SECONDS = 30
TRANSACTION_PAGINATION_MAX_PAGES_DEFAULT = 1000
TRANSACTION_PAGINATION_MAX_PAGES_ENV = "TELLER_TXN_MAX_PAGES"

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
        token = self._auth_token
        if not token:
            default_token_path = TELLER_DIR / "auth_token.json"
            if not default_token_path.is_file():
                raise TellerAPIError(
                    message=(
                        f"Missing auth token at {default_token_path}. "
                        "Use the macOS app Connect tab and click Add or Edit to save a connection token."
                    ),
                    code="auth_token.missing",
                    status_code=0,
                )
            try:
                token = json.loads(default_token_path.read_text()).get("current", "")
            except json.JSONDecodeError as exc:
                raise TellerAPIError(
                    message=f"Invalid auth token JSON at {default_token_path}: {exc}",
                    code="auth_token.invalid_json",
                    status_code=0,
                ) from exc
            if not token:
                raise TellerAPIError(
                    message=(
                        f"Auth token file {default_token_path} has no 'current' token value. "
                        "Use the macOS app Connect tab and re-save the connection."
                    ),
                    code="auth_token.empty",
                    status_code=0,
                )
        self.kwargs = {
            'auth': (token, ""),
            'cert': (str(TELLER_DIR / "certificate.pem"), str(TELLER_DIR / "private_key.pem")),
            'headers': {"Accept": "application/json", "Content-Type": "application/json"},
            'verify': True,
        }

    def _parse_error(self, response) -> tuple:
        try:
            err = response.json().get("error", {})
            code, message = err.get("code", ""), err.get("message", response.text)
        except ValueError:
            code, message = "", response.text
        return code, message

    def _repair_enrollment(self) -> bool:
        #R010: Attempt local Teller Connect repair through macOS UI.
        enrollment_id_file = TELLER_DIR / "enrollment_id.txt"
        enrollment_id = self._enrollment_id or (enrollment_id_file.read_text().strip() if enrollment_id_file.is_file() else "")
        repaired = False
        if enrollment_id:
            if not (sys.stdin.isatty() and sys.stdout.isatty()):
                raise TellerAPIError(
                    message=(
                        "Enrollment disconnected in a non-interactive session. "
                        "Manual reconnect is required. Run ./10_run_classification_macos_ui.sh "
                        "and use the Connect tab, then rerun this script."
                    ),
                    code="enrollment.disconnected.manual_repair_required",
                    status_code=0,
                )
            try:
                launcher = Path(__file__).resolve().parent / "10_run_classification_macos_ui.sh"
                if not launcher.is_file():
                    raise OSError(f"Missing launcher: {launcher}")
                if not os.access(launcher, os.X_OK):
                    raise OSError(f"Launcher is not executable: {launcher}")
                print(
                    f"Enrollment disconnected — repairing {enrollment_id} via macOS Connect UI.\n"
                    "The app will open on the Connect tab. Complete reconnect there, then return here."
                )
                env = os.environ.copy()
                env["TELLER_MACOS_START_TAB"] = "connect"
                subprocess.Popen([str(launcher)], env=env)
                input("Press Enter after reconnect is complete to retry Teller API calls...")
                self._load_auth()
                repaired = True
                print("Enrollment repair step completed. Resuming...")
            except (OSError, subprocess.SubprocessError) as exc:
                log.warning("Auto-repair failed", error=str(exc))
        else:
            log.warning("Cannot auto-repair: no enrollment ID", path=str(enrollment_id_file))
        return repaired

    def get(self, url: str, params: Dict = None) -> dict:
        log.info("Connecting to Teller API", url=url, params=params, has_auth=bool(self.kwargs.get("auth", ("", ""))[0]))
        response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT_SECONDS, **self.kwargs)
        code = self._parse_error(response)[0] if response.status_code != 200 else ""
        #R010: Retry once after successful enrollment repair.
        if code.startswith("enrollment.disconnected") and self._repair_enrollment():
            log.info("Retrying after enrollment repair", url=url)
            response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT_SECONDS, **self.kwargs)
        #R040: Non-disconnected API failures (including rate limit responses) fail fast without
        #R040: repair retry and propagate the upstream status/code/message deterministically.
        if response.status_code != 200:
            code, message = self._parse_error(response)
            raise TellerAPIError(message=message, code=code, status_code=response.status_code)
        return response.json()


def _resolve_transaction_pagination_max_pages() -> int:
    raw_max_pages = os.getenv(TRANSACTION_PAGINATION_MAX_PAGES_ENV, "").strip()
    if not raw_max_pages:
        return TRANSACTION_PAGINATION_MAX_PAGES_DEFAULT
    try:
        parsed = int(raw_max_pages)
    except ValueError:
        log.warning(
            "Invalid pagination max pages; using default",
            env_var=TRANSACTION_PAGINATION_MAX_PAGES_ENV,
            value=raw_max_pages,
            default=TRANSACTION_PAGINATION_MAX_PAGES_DEFAULT,
        )
        return TRANSACTION_PAGINATION_MAX_PAGES_DEFAULT
    if parsed <= 0:
        log.warning(
            "Non-positive pagination max pages; using default",
            env_var=TRANSACTION_PAGINATION_MAX_PAGES_ENV,
            value=raw_max_pages,
            default=TRANSACTION_PAGINATION_MAX_PAGES_DEFAULT,
        )
        return TRANSACTION_PAGINATION_MAX_PAGES_DEFAULT
    return parsed


def _fetch_all_transactions(client, txn_url):
    #R015: Fetch complete transaction history by paging with from_id cursor.
    max_pages = _resolve_transaction_pagination_max_pages()
    page_count = 0
    seen_last_ids = set()
    all_txns, page = [], client.get(txn_url)
    while page:
        page_count += 1
        if page_count > max_pages:
            raise TellerAPIError(
                message=(
                    f"Transaction pagination exceeded maximum pages ({max_pages}). "
                    f"Set {TRANSACTION_PAGINATION_MAX_PAGES_ENV} to a larger value if needed."
                ),
                code="transactions.pagination.max_pages_exceeded",
                status_code=0,
            )
        all_txns.extend(page)
        last_id = page[-1]["id"]
        if last_id in seen_last_ids:
            raise TellerAPIError(
                message=(
                    "Transaction pagination repeated the same cursor value. "
                    f"Detected repeated from_id={last_id} after {page_count} pages."
                ),
                code="transactions.pagination.repeated_cursor",
                status_code=0,
            )
        seen_last_ids.add(last_id)
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
                        "source": "metadata",
                    })
    return contexts

def _load_suffix_contexts() -> List[dict]:
    contexts = []
    for token_file in sorted(TELLER_DIR.glob("auth_token_*.json")):
        suffix = token_file.stem.removeprefix("auth_token_")
        if not suffix:
            log.warning("Skipping malformed suffix token filename", path=str(token_file))
            continue
        contexts.append({
            "enrollment_id": _read_text_file(TELLER_DIR / f"enrollment_id_{suffix}.txt"),
            "token": _read_token_file(token_file),
            "institution_id": suffix,
            "source": "suffix",
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
        source = row.get("source", "")
        token_fingerprint = hashlib.sha256(token.encode("utf-8")).hexdigest()[:12] if token else ""
        key = enrollment_id or f"{institution_id}:{token_fingerprint}"
        if key:
            deduped[key] = {
                "enrollment_id": enrollment_id,
                "token": token,
                "institution_id": institution_id,
                "source": source,
            }
    return list(deduped.values())

def _fetch_context_data(client: TellerAPIClient, institution_id: str) -> tuple:
    raw_identities = client.get(f"{client.BASE_URL}/identity")
    filtered_identities = [item for item in raw_identities if not institution_id or
                           item["account"]["institution"]["id"] == institution_id]
    raw_transactions_by_account, raw_balances_by_account = {}, {}
    for item in filtered_identities:
        account_data = item["account"]
        account = TellerAccount(account_data)
        print(f"Account fetched: id={account.id} institution={account.institution.name}")
        raw_txns = _fetch_all_transactions(client, account.links.transactions)
        raw_transactions_by_account[account_data["id"]] = raw_txns
        print(f"  Transactions fetched: {len(raw_txns)}")
        if account.links.balances:
            raw_bal = client.get(account.links.balances)
            raw_balances_by_account[account_data["id"]] = raw_bal
            print("  Balances fetched.")
        print(f"  Owners fetched: {len(item.get('owners', []))}")
    return filtered_identities, raw_transactions_by_account, raw_balances_by_account

def _build_enrollment_contexts(institution_id: str) -> List[dict]:
    #R020: Merge default/metadata/suffix enrollment contexts, then dedupe and optionally scope by institution.
    contexts = []
    default_token = _read_token_file(TELLER_DIR / "auth_token.json")
    if default_token:
        contexts.append({
            "enrollment_id": _read_text_file(TELLER_DIR / "enrollment_id.txt"),
            "token": default_token,
            "institution_id": "",
            "source": "default",
        })
    contexts.extend(_load_metadata_contexts())
    contexts.extend(_load_suffix_contexts())
    contexts = _dedupe_contexts(contexts)
    if institution_id:
        matched = [row for row in contexts if row.get("institution_id") == institution_id]
        if not matched:
            inferred = _infer_enrollment_ids_from_db(institution_id)
            matched = [{"enrollment_id": enrollment_id, "token": "", "institution_id": institution_id, "source": "inferred"}
                       for enrollment_id in inferred]
        contexts = matched if matched else contexts
    contexts = contexts if contexts else [{"enrollment_id": "", "token": "", "institution_id": "", "source": "fallback"}]
    return contexts

def main():
    # New files/dirs from this process: no group/other access (aligns with umask 007 in shell scripts).
    os.umask(0o007)
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
                print(f"Fetched identity records: {len(ids)}")
                raw_identities.extend(ids)
                raw_transactions_by_account.update(tx_by_account)
                raw_balances_by_account.update(bals_by_account)
            except TellerAPIError as exc:
                errors.append(
                    {
                        "institution_id": context.get("institution_id", ""),
                        "enrollment_id": context.get("enrollment_id", ""),
                        "source": context.get("source", "unknown"),
                        "status_code": exc.status_code,
                        "message": exc.message,
                        "code": exc.code,
                    }
                )
        if not raw_identities and errors:
            first = errors[0]
            raise TellerAPIError(message=first["message"], code=first["code"], status_code=first["status_code"])
        if errors:
            for err in errors:
                print(
                    "Enrollment failed: "
                    f"institution_id={err['institution_id']} "
                    f"enrollment_id={err['enrollment_id']} "
                    f"source={err.get('source', 'unknown')}"
                )
                print(f"  status={err['status_code']} code={err['code']} message={err['message']}")
        #R025: Persist fetched Teller data unless running in dry-run mode.
        if not args.dry_run:
            from teller.teller_db import get_session
            from teller.teller_persist import persist_all
            session = get_session()
            try:
                #R030: Transaction canonicalization is handled inside persist_all.
                #R035: Stale-graph cleanup is handled inside persist_all.
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
            print("Auto-repair failed. Run ./10_run_classification_macos_ui.sh and use the Connect tab to repair.")
        sys.exit(1)

if __name__ == "__main__":
    main()