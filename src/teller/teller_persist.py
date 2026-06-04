"""Persistence helpers for Teller ingestion workflows.

#R001: Shared SQL execution and persistence helper behavior.
#R005: Idempotent account upsert orchestration behavior.
#R010: Identity graph upsert and linkage behavior.
#R015: Transaction typing and amount normalization behavior.
#R020: Transaction upsert lifecycle behavior.
#R025: Balance upsert and account-balance synchronization behavior.
#R030: Canonical transaction reconciliation behavior.
#R035: Stale graph cleanup behavior.
#R040: Commit/rollback persistence boundary behavior.
"""

from decimal import Decimal, ROUND_HALF_UP
from sqlalchemy import bindparam, text
import structlog

log = structlog.get_logger()
_USD_QUANTUM = Decimal("0.01")

#R045: SQLite execution helper must coerce unsupported bound parameter types.
def _sqlite_safe_params(params):
    if isinstance(params, Decimal):
        return str(params)
    if isinstance(params, dict):
        return {key: _sqlite_safe_params(value) for key, value in params.items()}
    if isinstance(params, list):
        return [_sqlite_safe_params(value) for value in params]
    if isinstance(params, tuple):
        return tuple(_sqlite_safe_params(value) for value in params)
    return params


def _is_sqlite_session(session):
    dialect = getattr(getattr(session, "bind", None), "dialect", None)
    return getattr(dialect, "name", None) == "sqlite"


def _sqlite_money_to_minor_units(value):
    if value is None:
        return None
    quantized = value.quantize(_USD_QUANTUM, rounding=ROUND_HALF_UP)
    return int(quantized * 100)


#R001: Shared SQL execution helper.
def _exec(session, sql, params=None):
    bound_params = params or {}
    if _is_sqlite_session(session):
        bound_params = _sqlite_safe_params(bound_params)
    return session.execute(text(sql), bound_params)

#R001: Shared SQL execution helper with RETURNING row support.
def _exec_returning(session, sql, params=None):
    return _exec(session, sql, params).fetchone()

def _upsert_institution(session, inst_data):
    _exec(session, """
        INSERT INTO teller.institution (institution_id, name)
        VALUES (:id, :name)
        ON CONFLICT (institution_id) DO UPDATE SET name = EXCLUDED.name
    """, {"id": inst_data["id"], "name": inst_data["name"]})

def _upsert_account_links(session, links_data, existing_links_id=None):
    vals = {"self_link": links_data.get("self", ""), "details": links_data.get("details"),
            "balances": links_data.get("balances"), "transactions": links_data.get("transactions")}
    if existing_links_id:
        _exec(session, """
            UPDATE teller.account_links
            SET self_link = :self_link, details = :details, balances = :balances, transactions = :transactions
            WHERE account_links_id = :id
        """, {**vals, "id": existing_links_id})
        return existing_links_id
    row = _exec_returning(session, """
        INSERT INTO teller.account_links (self_link, details, balances, transactions)
        VALUES (:self_link, :details, :balances, :transactions)
        RETURNING account_links_id
    """, vals)
    return row[0]

#R005: Idempotent account-level upsert orchestration.
def _upsert_account(session, account_data):
    acct_id = account_data["id"]
    currency_code = account_data["currency"]
    if _is_sqlite_session(session) and currency_code != "USD":
        raise ValueError(f"SQLite money storage expects USD accounts; got currency={currency_code!r} account_id={acct_id!r}")
    inst_data, links_data = account_data["institution"], account_data["links"]
    _upsert_institution(session, inst_data)
    existing = _exec(session, "SELECT account_links_id FROM teller.account WHERE account_id = :id", {"id": acct_id}).fetchone()
    links_id = _upsert_account_links(session, links_data, existing[0] if existing else None)
    vals = {"account_id": acct_id, "currency": currency_code, "enrollment_id": account_data["enrollment_id"],
            "institution_id": inst_data["id"], "last_four": account_data["last_four"], "account_links_id": links_id,
            "name": account_data["name"], "type": account_data["type"], "subtype": account_data["subtype"],
            "status": account_data["status"]}
    _exec(session, """
        INSERT INTO teller.account (account_id, currency, enrollment_id, institution_id, last_four, account_links_id, name, type, subtype, status)
        VALUES (:account_id, :currency, :enrollment_id, :institution_id, :last_four, :account_links_id, :name, :type, :subtype, :status)
        ON CONFLICT (account_id) DO UPDATE SET
            currency = EXCLUDED.currency, enrollment_id = EXCLUDED.enrollment_id, institution_id = EXCLUDED.institution_id,
            last_four = EXCLUDED.last_four, name = EXCLUDED.name, type = EXCLUDED.type, subtype = EXCLUDED.subtype, status = EXCLUDED.status
    """, vals)

#R010: Identity graph upsert and reuse via known email linkage.
def _existing_identity_id_by_email(session, emails):
    for email_data in emails:
        row = _exec(session, "SELECT identity_id FROM teller.identity_email WHERE data = :data", {"data": email_data["data"]}).fetchone()
        if row:
            return row[0]
    return None


def _upsert_identity_record(session, owner_type, identity_id=None):
    if identity_id:
        _exec(session, "UPDATE teller.identity SET type = :type WHERE identity_id = :id", {"type": owner_type, "id": identity_id})
        return identity_id
    return _exec_returning(session, """
        INSERT INTO teller.identity (type) VALUES (:type) RETURNING identity_id
    """, {"type": owner_type})[0]


def _upsert_identity_names(session, names, identity_id):
    for n in names:
        _exec(session, """
            INSERT INTO teller.identity_name (type, data, identity_id)
            VALUES (:type, :data, :identity_id)
            ON CONFLICT (data, identity_id) DO UPDATE SET type = EXCLUDED.type
        """, {"type": n["type"], "data": n["data"], "identity_id": identity_id})


def _upsert_identity_emails(session, emails, identity_id):
    for e in emails:
        _exec(session, """
            INSERT INTO teller.identity_email (data, identity_id)
            VALUES (:data, :identity_id)
            ON CONFLICT (data) DO NOTHING
        """, {"data": e["data"], "identity_id": identity_id})


def _upsert_identity_phone_numbers(session, phone_numbers, identity_id):
    for p in phone_numbers:
        _exec(session, """
            INSERT INTO teller.identity_phone_number (type, data, identity_id)
            VALUES (:type, :data, :identity_id)
            ON CONFLICT (data, identity_id) DO UPDATE SET type = EXCLUDED.type
        """, {"type": p["type"], "data": p["data"], "identity_id": identity_id})


def _upsert_identity_addresses(session, addresses, identity_id):
    for a in addresses:
        addr = a["data"]
        addr_data_id = _exec_returning(session, """
            INSERT INTO teller.identity_address_data (street, city, region, country, postal_code)
            VALUES (:street, :city, :region, :country, :postal_code)
            ON CONFLICT (street, city, region, country, postal_code) DO UPDATE SET street = EXCLUDED.street
            RETURNING identity_address_data_id
        """, addr)[0]
        _exec(session, """
            INSERT INTO teller.identity_address (primary_address, identity_address_data_id, identity_id)
            VALUES (:primary, :addr_data_id, :identity_id)
            ON CONFLICT (identity_address_data_id, identity_id) DO UPDATE SET primary_address = EXCLUDED.primary_address
        """, {"primary": a.get("primary", False), "addr_data_id": addr_data_id, "identity_id": identity_id})


def _upsert_identity(session, owner_data):
    emails = owner_data.get("emails") or []
    identity_id = None
    identity_id = _existing_identity_id_by_email(session, emails)
    identity_id = _upsert_identity_record(session, owner_data["type"], identity_id)
    _upsert_identity_names(session, owner_data.get("names") or [], identity_id)
    _upsert_identity_emails(session, emails, identity_id)
    _upsert_identity_phone_numbers(session, owner_data.get("phone_numbers") or [], identity_id)
    _upsert_identity_addresses(session, owner_data.get("addresses") or [], identity_id)
    return identity_id

def _upsert_account_identity(session, account_id, identity_id):
    _exec(session, """
        INSERT INTO teller.account_identities (account_id, identity_id)
        VALUES (:account_id, :identity_id)
        ON CONFLICT (account_id, identity_id) DO NOTHING
    """, {"account_id": account_id, "identity_id": identity_id})

def _upsert_transaction_type(session, type_code):
    row = _exec(session, "SELECT transaction_type_id FROM teller.transaction_type WHERE code = :code", {"code": type_code}).fetchone()
    if row:
        return row[0]
    return _exec_returning(session, """
        INSERT INTO teller.transaction_type (code) VALUES (:code) RETURNING transaction_type_id
    """, {"code": type_code})[0]

def _upsert_transaction_links(session, links_data, existing_links_id=None):
    self_link = links_data.get("self", "")
    account_link = links_data.get("account", "")
    if existing_links_id:
        _exec(session, """
            UPDATE teller.transaction_links SET self_link = :self_link, account = :account WHERE transaction_links_id = :id
        """, {"self_link": self_link, "account": account_link, "id": existing_links_id})
        return existing_links_id
    row = _exec(session, "SELECT transaction_links_id FROM teller.transaction_links WHERE self_link = :sl", {"sl": self_link}).fetchone()
    if row:
        return row[0]
    return _exec_returning(session, """
        INSERT INTO teller.transaction_links (self_link, account)
        VALUES (:self_link, :account)
        ON CONFLICT (self_link) DO UPDATE SET account = EXCLUDED.account
        RETURNING transaction_links_id
    """, {"self_link": self_link, "account": account_link})[0]

def _upsert_transaction_details(session, details_data, existing_details_id=None):
    counterparty_id = None
    cp = details_data.get("counterparty")
    if cp and cp.get("name"):
        row = _exec(session, """
            SELECT transaction_details_counterparty_id FROM teller.transaction_details_counterparty
            WHERE name = :name AND type = :type
        """, {"name": cp["name"], "type": cp["type"]}).fetchone()
        if row:
            counterparty_id = row[0]
        else:
            counterparty_id = _exec_returning(session, """
                INSERT INTO teller.transaction_details_counterparty (name, type)
                VALUES (:name, :type) RETURNING transaction_details_counterparty_id
            """, {"name": cp["name"], "type": cp["type"]})[0]
    vals = {"processing_status": details_data["processing_status"],
            "category": details_data.get("category"), "transaction_details_counterparty_id": counterparty_id}
    if existing_details_id:
        _exec(session, """
            UPDATE teller.transaction_details
            SET processing_status = :processing_status, category = :category,
                transaction_details_counterparty_id = :transaction_details_counterparty_id
            WHERE transaction_details_id = :id
        """, {**vals, "id": existing_details_id})
        return existing_details_id
    return _exec_returning(session, """
        INSERT INTO teller.transaction_details (processing_status, category, transaction_details_counterparty_id)
        VALUES (:processing_status, :category, :transaction_details_counterparty_id)
        RETURNING transaction_details_id
    """, vals)[0]

#R015: Transaction upsert with relation normalization and decimal casting.
def _upsert_transaction(session, txn_data):
    txn_id = txn_data["id"]
    #R050: Quote reserved transaction table name for SQLite/PostgreSQL compatibility.
    existing = _exec(session, """
        SELECT transaction_details_id, transaction_links_id FROM teller."transaction" WHERE transaction_id = :id
    """, {"id": txn_id}).fetchone()
    type_id = _upsert_transaction_type(session, txn_data["type"])
    details_id = _upsert_transaction_details(session, txn_data["details"], existing[0] if existing else None)
    links_id = _upsert_transaction_links(session, txn_data["links"], existing[1] if existing else None)
    amount = Decimal(txn_data["amount"])
    running_balance = Decimal(txn_data["running_balance"]) if txn_data.get("running_balance") else None
    if _is_sqlite_session(session):
        amount = _sqlite_money_to_minor_units(amount)
        running_balance = _sqlite_money_to_minor_units(running_balance)
    vals = {"transaction_id": txn_id, "account_id": txn_data["account_id"], "amount": amount,
            "date": txn_data["date"], "description": txn_data["description"],
            "transaction_details_id": details_id, "status": txn_data["status"],
            "transaction_links_id": links_id, "running_balance": running_balance,
            "transaction_type_id": type_id}
    _exec(session, """
        INSERT INTO teller."transaction"
            (transaction_id, account_id, amount, date, description, transaction_details_id, status, transaction_links_id, running_balance, transaction_type_id)
        VALUES (:transaction_id, :account_id, :amount, :date, :description, :transaction_details_id, :status, :transaction_links_id, :running_balance, :transaction_type_id)
        ON CONFLICT (transaction_id) DO UPDATE SET
            account_id = EXCLUDED.account_id,
            amount = EXCLUDED.amount,
            date = EXCLUDED.date,
            description = EXCLUDED.description,
            transaction_details_id = EXCLUDED.transaction_details_id,
            status = EXCLUDED.status,
            transaction_links_id = EXCLUDED.transaction_links_id,
            running_balance = EXCLUDED.running_balance,
            transaction_type_id = EXCLUDED.transaction_type_id,
            updated_at = CURRENT_TIMESTAMP
    """, vals)

def _canonicalize_transactions(txns):
    #R030: Canonicalize duplicate IDs so posted snapshots win over pending.
    by_id = {}
    for txn_data in txns:
        txn_id = txn_data["id"]
        existing = by_id.get(txn_id)
        if not existing:
            by_id[txn_id] = txn_data
            continue
        existing_status = existing.get("status")
        incoming_status = txn_data.get("status")
        if existing_status != "posted" and incoming_status == "posted":
            by_id[txn_id] = txn_data
    return list(by_id.values())

def _reconcile_missing_pending_transactions(session, account_id, fetched_transaction_ids):
    #R025: Delete stale pending transactions absent from current fetch.
    if not fetched_transaction_ids:
        return []
    deleted = session.execute(
        text(
            """
            DELETE FROM teller."transaction"
            WHERE account_id = :account_id
              AND status = 'pending'
              AND transaction_id NOT IN :fetched_ids
            RETURNING transaction_id
        """
        ).bindparams(bindparam("fetched_ids", expanding=True)),
        {"account_id": account_id, "fetched_ids": fetched_transaction_ids},
    ).fetchall()
    return [row[0] for row in deleted]

def _prune_unreferenced_transaction_relations(session):
    #R030: Remove orphaned transaction relation rows after reconciliation.
    #R055: SQLite portability - avoid aliasing the DELETE target table.
    removed_links = _exec(session, """
        DELETE FROM teller.transaction_links
        WHERE NOT EXISTS (
            SELECT 1
            FROM teller."transaction" t
            WHERE t.transaction_links_id = teller.transaction_links.transaction_links_id
        )
        RETURNING transaction_links_id
    """).fetchall()
    removed_details = _exec(session, """
        DELETE FROM teller.transaction_details
        WHERE NOT EXISTS (
            SELECT 1
            FROM teller."transaction" t
            WHERE t.transaction_details_id = teller.transaction_details.transaction_details_id
        )
        RETURNING transaction_details_id
    """).fetchall()
    removed_counterparties = _exec(session, """
        DELETE FROM teller.transaction_details_counterparty
        WHERE NOT EXISTS (
            SELECT 1
            FROM teller.transaction_details td
            WHERE td.transaction_details_counterparty_id = teller.transaction_details_counterparty.transaction_details_counterparty_id
        )
        RETURNING transaction_details_counterparty_id
    """).fetchall()
    return {
        "transaction_links": len(removed_links),
        "transaction_details": len(removed_details),
        "transaction_details_counterparty": len(removed_counterparties),
    }

def _upsert_account_balances_links(session, links_data, existing_links_id=None):
    self_link = links_data.get("self", "")
    account_link = links_data.get("account", "")
    if existing_links_id:
        _exec(session, """
            UPDATE teller.account_balances_links SET self_link = :self_link, account_link = :account_link
            WHERE account_balances_links_id = :id
        """, {"self_link": self_link, "account_link": account_link, "id": existing_links_id})
        return existing_links_id
    row = _exec(session, "SELECT account_balances_links_id FROM teller.account_balances_links WHERE self_link = :sl",
                {"sl": self_link}).fetchone()
    if row:
        return row[0]
    return _exec_returning(session, """
        INSERT INTO teller.account_balances_links (self_link, account_link)
        VALUES (:self_link, :account_link)
        ON CONFLICT (self_link) DO UPDATE SET account_link = EXCLUDED.account_link
        RETURNING account_balances_links_id
    """, {"self_link": self_link, "account_link": account_link})[0]

#R035: Account balances upsert with optional decimal fields.
def _upsert_account_balances(session, bal_data):
    account_id = bal_data["account_id"]
    existing = _exec(session, """
        SELECT account_balances_id, account_balances_links_id FROM teller.account_balances WHERE account_id = :id
    """, {"id": account_id}).fetchone()
    links_id = _upsert_account_balances_links(session, bal_data["links"], existing[1] if existing else None)
    ledger = Decimal(bal_data["ledger"]) if bal_data.get("ledger") else None
    available = Decimal(bal_data["available"]) if bal_data.get("available") else None
    if _is_sqlite_session(session):
        ledger = _sqlite_money_to_minor_units(ledger)
        available = _sqlite_money_to_minor_units(available)
    vals = {"account_id": account_id, "ledger": ledger, "available": available, "account_balances_links_id": links_id}
    if existing:
        _exec(session, """
            UPDATE teller.account_balances SET ledger = :ledger, available = :available,
                account_balances_links_id = :account_balances_links_id, updated_at = CURRENT_TIMESTAMP
            WHERE account_id = :account_id
        """, vals)
    else:
        _exec(session, """
            INSERT INTO teller.account_balances (account_id, ledger, available, account_balances_links_id)
            VALUES (:account_id, :ledger, :available, :account_balances_links_id)
        """, vals)

#R040: Persist identities, balances, transactions, then commit once.
def persist_all(session, raw_identities, raw_transactions_by_account, raw_balances_by_account=None):
    try:
        for item in raw_identities:
            account_data = item["account"]
            _upsert_account(session, account_data)
            for owner_data in item["owners"]:
                identity_id = _upsert_identity(session, owner_data)
                _upsert_account_identity(session, account_data["id"], identity_id)
            log.info("Persisted account + identities", account_id=account_data["id"], owner_count=len(item["owners"]))
        for account_id, bal_data in (raw_balances_by_account or {}).items():
            _upsert_account_balances(session, bal_data)
            log.info("Persisted balances", account_id=account_id, ledger=bal_data.get("ledger"), available=bal_data.get("available"))
        for account_id, txns in raw_transactions_by_account.items():
            canonical_txns = _canonicalize_transactions(txns)
            for txn_data in canonical_txns:
                _upsert_transaction(session, txn_data)
            fetched_transaction_ids = [txn_data["id"] for txn_data in canonical_txns]
            deleted_pending_ids = []
            if fetched_transaction_ids:
                deleted_pending_ids = _reconcile_missing_pending_transactions(
                    session,
                    account_id,
                    fetched_transaction_ids,
                )
            log.info("Persisted transactions", account_id=account_id, count=len(canonical_txns))
            if deleted_pending_ids:
                log.info("Removed stale pending transactions", account_id=account_id, count=len(deleted_pending_ids))
        pruned = _prune_unreferenced_transaction_relations(session)
        if any(pruned.values()):
            log.info("Pruned unreferenced transaction relation rows", **pruned)
        session.commit()
        log.info("Database commit complete")
    except Exception:
        if hasattr(session, "rollback"):
            session.rollback()
        raise
