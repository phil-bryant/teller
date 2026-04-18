from decimal import Decimal
from sqlalchemy import text
import structlog

log = structlog.get_logger()

def _exec(session, sql, params=None):
    return session.execute(text(sql), params or {})

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

def _upsert_account(session, account_data):
    acct_id = account_data["id"]
    inst_data, links_data = account_data["institution"], account_data["links"]
    _upsert_institution(session, inst_data)
    existing = _exec(session, "SELECT account_links_id FROM teller.account WHERE account_id = :id", {"id": acct_id}).fetchone()
    links_id = _upsert_account_links(session, links_data, existing[0] if existing else None)
    vals = {"account_id": acct_id, "currency": account_data["currency"], "enrollment_id": account_data["enrollment_id"],
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

def _upsert_identity(session, owner_data):
    identity_id = None
    for email_data in (owner_data.get("emails") or []):
        row = _exec(session, "SELECT identity_id FROM teller.identity_email WHERE data = :data", {"data": email_data["data"]}).fetchone()
        if row:
            identity_id = row[0]
    if identity_id:
        _exec(session, "UPDATE teller.identity SET type = :type WHERE identity_id = :id", {"type": owner_data["type"], "id": identity_id})
    else:
        identity_id = _exec_returning(session, """
            INSERT INTO teller.identity (type) VALUES (:type) RETURNING identity_id
        """, {"type": owner_data["type"]})[0]
    for n in (owner_data.get("names") or []):
        _exec(session, """
            INSERT INTO teller.identity_name (type, data, identity_id)
            VALUES (:type, :data, :identity_id)
            ON CONFLICT (data, identity_id) DO UPDATE SET type = EXCLUDED.type
        """, {"type": n["type"], "data": n["data"], "identity_id": identity_id})
    for e in (owner_data.get("emails") or []):
        _exec(session, """
            INSERT INTO teller.identity_email (data, identity_id)
            VALUES (:data, :identity_id)
            ON CONFLICT (data) DO UPDATE SET identity_id = EXCLUDED.identity_id
        """, {"data": e["data"], "identity_id": identity_id})
    for p in (owner_data.get("phone_numbers") or []):
        _exec(session, """
            INSERT INTO teller.identity_phone_number (type, data, identity_id)
            VALUES (:type, :data, :identity_id)
            ON CONFLICT (data, identity_id) DO UPDATE SET type = EXCLUDED.type
        """, {"type": p["type"], "data": p["data"], "identity_id": identity_id})
    for a in (owner_data.get("addresses") or []):
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

def _upsert_transaction(session, txn_data):
    txn_id = txn_data["id"]
    existing = _exec(session, """
        SELECT transaction_details_id, transaction_links_id FROM teller.transaction WHERE transaction_id = :id
    """, {"id": txn_id}).fetchone()
    type_id = _upsert_transaction_type(session, txn_data["type"])
    details_id = _upsert_transaction_details(session, txn_data["details"], existing[0] if existing else None)
    links_id = _upsert_transaction_links(session, txn_data["links"], existing[1] if existing else None)
    amount = Decimal(txn_data["amount"])
    running_balance = Decimal(txn_data["running_balance"]) if txn_data.get("running_balance") else None
    vals = {"transaction_id": txn_id, "account_id": txn_data["account_id"], "amount": amount,
            "date": txn_data["date"], "description": txn_data["description"],
            "transaction_details_id": details_id, "status": txn_data["status"],
            "transaction_links_id": links_id, "running_balance": running_balance,
            "transaction_type_id": type_id}
    _exec(session, """
        INSERT INTO teller.transaction
            (transaction_id, account_id, amount, date, description, transaction_details_id, status, transaction_links_id, running_balance, transaction_type_id)
        VALUES (:transaction_id, :account_id, :amount, :date, :description, :transaction_details_id, :status, :transaction_links_id, :running_balance, :transaction_type_id)
        ON CONFLICT (transaction_id) DO UPDATE SET
            amount = EXCLUDED.amount, date = EXCLUDED.date, description = EXCLUDED.description,
            status = EXCLUDED.status, running_balance = EXCLUDED.running_balance, transaction_type_id = EXCLUDED.transaction_type_id
    """, vals)

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

def _upsert_account_balances(session, bal_data):
    account_id = bal_data["account_id"]
    existing = _exec(session, """
        SELECT account_balances_id, account_balances_links_id FROM teller.account_balances WHERE account_id = :id
    """, {"id": account_id}).fetchone()
    links_id = _upsert_account_balances_links(session, bal_data["links"], existing[1] if existing else None)
    ledger = Decimal(bal_data["ledger"]) if bal_data.get("ledger") else None
    available = Decimal(bal_data["available"]) if bal_data.get("available") else None
    vals = {"account_id": account_id, "ledger": ledger, "available": available, "account_balances_links_id": links_id}
    if existing:
        _exec(session, """
            UPDATE teller.account_balances SET ledger = :ledger, available = :available,
                account_balances_links_id = :account_balances_links_id
            WHERE account_id = :account_id
        """, vals)
    else:
        _exec(session, """
            INSERT INTO teller.account_balances (account_id, ledger, available, account_balances_links_id)
            VALUES (:account_id, :ledger, :available, :account_balances_links_id)
        """, vals)

def persist_all(session, raw_identities, raw_transactions_by_account, raw_balances_by_account=None):
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
        for txn_data in txns:
            _upsert_transaction(session, txn_data)
        log.info("Persisted transactions", account_id=account_id, count=len(txns))
    session.commit()
    log.info("Database commit complete")
