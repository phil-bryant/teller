import unittest
from decimal import Decimal
from unittest.mock import MagicMock, patch

from teller import teller_persist


class _Result:
    #R001: Initialize persistence test doubles with execution capture state.
    def __init__(self, one=None, many=None):
        self._one = one
        self._many = many or []

    #R001: Return one-row SQL result for persistence helper tests.
    def fetchone(self):
        return self._one

    #R001: Return multi-row SQL result for persistence helper tests.
    def fetchall(self):
        return self._many


class _Session:
    #R001: Initialize persistence test doubles with execution capture state.
    def __init__(self, execute_result):
        self.execute_result = execute_result
        self.calls = []
        self.commits = 0
        self.rollbacks = 0

    #R001: Capture SQL execution calls for persistence assertions.
    def execute(self, sql, params):
        self.calls.append((sql, params))
        return self.execute_result

    #R001: Track commit invocations in persistence test session.
    def commit(self):
        self.commits += 1

    #R001: Track rollback invocations in persistence test session.
    def rollback(self):
        self.rollbacks += 1


class _SQLiteSession(_Session):
    #R001: Initialize persistence test doubles with execution capture state.
    def __init__(self, execute_result):
        super().__init__(execute_result)
        self.bind = type("Bind", (), {"dialect": type("Dialect", (), {"name": "sqlite"})()})()


class TellerPersistTests(unittest.TestCase):
    def test_exec_executes_parameterized_sql(self):
        #R001-T01: Run helper calls against a test session and verify parameterized statements execute and returning rows are accessible.
        session = _Session(_Result())
        teller_persist._exec(session, "SELECT :value", {"value": 7})
        sql, params = session.calls[0]
        self.assertIn("SELECT :value", str(sql))
        self.assertEqual(params, {"value": 7})

    def test_exec_coerces_decimal_params_for_sqlite_binding(self):
        #R045-T01: Execute `_exec` with a SQLite-bound session and `Decimal` parameter, and verify bound params are coerced before `session.execute`.
        session = _SQLiteSession(_Result())
        teller_persist._exec(session, "SELECT :amount", {"amount": Decimal("12.34")})
        _, params = session.calls[0]
        self.assertEqual(params["amount"], "12.34")

    def test_exec_returning_returns_single_row(self):
        #R001-T01: Run helper calls against a test session and verify parameterized statements execute and returning rows are accessible.
        session = _Session(_Result(one=(123,)))
        row = teller_persist._exec_returning(session, "SELECT 1")
        self.assertEqual(row, (123,))

    @patch("teller.teller_persist._exec")
    @patch("teller.teller_persist._upsert_account_links")
    @patch("teller.teller_persist._upsert_institution")
    def test_upsert_account_reuses_existing_account_links_id(self, upsert_institution, upsert_links, exec_mock):
        #R005-T01: Persist the same account payload twice and verify one logical account row remains with updated mutable fields.
        account_payload = {
            "id": "acc_1",
            "currency": "USD",
            "enrollment_id": "enr_1",
            "institution": {"id": "ins_1", "name": "Bank"},
            "last_four": "1234",
            "links": {"self": "s"},
            "name": "Checking",
            "type": "depository",
            "subtype": "checking",
            "status": "open",
        }
        exec_mock.return_value = _Result(one=(44,))
        upsert_links.return_value = 44

        session = MagicMock()
        teller_persist._upsert_account(session, account_payload)

        upsert_institution.assert_called_once_with(session, account_payload["institution"])
        upsert_links.assert_called_once_with(session, account_payload["links"], 44)
        insert_sql = str(exec_mock.call_args_list[-1].args[1])
        self.assertIn("ON CONFLICT (account_id) DO UPDATE", insert_sql)

    @patch("teller.teller_persist._exec")
    @patch("teller.teller_persist._exec_returning")
    def test_upsert_identity_reuses_existing_identity_by_email(self, exec_returning_mock, exec_mock):
        #R010-T01: Persist repeated owner payloads and verify identity rows are reused/updated rather than duplicated.
        owner_payload = {
            "type": "person",
            "names": [{"type": "legal", "data": "Pat Doe"}],
            "emails": [{"data": "pat@example.com"}],
            "phone_numbers": [{"type": "mobile", "data": "555-1234"}],
            "addresses": [],
        }

        exec_mock.side_effect = [
            _Result(one=(77,)),  # existing identity by email
            _Result(),  # update identity
            _Result(),  # insert name
            _Result(),  # insert email
            _Result(),  # insert phone
        ]

        session = MagicMock()
        identity_id = teller_persist._upsert_identity(session, owner_payload)

        self.assertEqual(identity_id, 77)
        exec_returning_mock.assert_not_called()
        self.assertIn("UPDATE teller.identity SET type", str(exec_mock.call_args_list[1].args[1]))

    @patch("teller.teller_persist._exec")
    def test_upsert_account_identity_is_conflict_safe(self, exec_mock):
        #R010-T02: Verify account-identity link insert is conflict-safe.
        session = MagicMock()
        teller_persist._upsert_account_identity(session, "acc_1", 5)
        sql = str(exec_mock.call_args.args[1])
        self.assertIn("ON CONFLICT (account_id, identity_id) DO NOTHING", sql)

    @patch("teller.teller_persist._exec")
    def test_upsert_identity_emails_does_not_reassign_existing_email_owner(self, exec_mock):
        #R010-T03: Verify identity-email upsert does not reassign ownership when the email already exists for another identity.
        session = MagicMock()
        teller_persist._upsert_identity_emails(session, [{"data": "pat@example.com"}], 7)
        sql = str(exec_mock.call_args.args[1])
        self.assertIn("ON CONFLICT (data) DO NOTHING", sql)
        self.assertNotIn("identity_id = EXCLUDED.identity_id", sql)

    @patch("teller.teller_persist._upsert_transaction_type", return_value=8)
    @patch("teller.teller_persist._upsert_transaction_details", return_value=9)
    @patch("teller.teller_persist._upsert_transaction_links", return_value=10)
    @patch("teller.teller_persist._exec")
    def test_upsert_transaction_casts_numeric_fields_and_writes_row(self, exec_mock, upsert_links, upsert_details, upsert_type):
        #R015-T01: Persist transaction payload with links/details and verify relational rows and transaction row are written.
        txn_payload = {
            "id": "txn_1",
            "account_id": "acc_1",
            "amount": "12.34",
            "date": "2026-01-01",
            "description": "Coffee",
            "details": {"processing_status": "complete"},
            "status": "posted",
            "links": {"self": "s", "account": "a"},
            "running_balance": "99.01",
            "type": "card_payment",
        }
        exec_mock.return_value = _Result(one=None)  # no existing transaction row

        session = MagicMock()
        teller_persist._upsert_transaction(session, txn_payload)

        sql = str(exec_mock.call_args_list[-1].args[1])
        params = exec_mock.call_args_list[-1].args[2]
        self.assertIn("ON CONFLICT (transaction_id) DO UPDATE", sql)
        self.assertEqual(params["amount"], Decimal("12.34"))
        self.assertEqual(params["running_balance"], Decimal("99.01"))
        upsert_type.assert_called_once()
        upsert_details.assert_called_once()
        upsert_links.assert_called_once()

    @patch("teller.teller_persist._upsert_transaction_type", return_value=8)
    @patch("teller.teller_persist._upsert_transaction_details", return_value=9)
    @patch("teller.teller_persist._upsert_transaction_links", return_value=10)
    @patch("teller.teller_persist._exec")
    def test_upsert_transaction_passes_existing_relation_ids_to_upserts(self, exec_mock, upsert_links, upsert_details, _upsert_type):
        #R015-T02: Re-persist with changed mutable fields and verify transaction conflict update path applies.
        exec_mock.return_value = _Result(one=(501, 601))
        txn_payload = {
            "id": "txn_2",
            "account_id": "acc_1",
            "amount": "1.00",
            "date": "2026-01-02",
            "description": "Lunch",
            "details": {"processing_status": "complete"},
            "status": "pending",
            "links": {"self": "s", "account": "a"},
            "type": "card_payment",
        }

        session = MagicMock()
        teller_persist._upsert_transaction(session, txn_payload)

        upsert_details.assert_called_once_with(session, txn_payload["details"], 501)
        upsert_links.assert_called_once_with(session, txn_payload["links"], 601)
        select_sql = str(exec_mock.call_args_list[0].args[1])
        self.assertIn('FROM teller."transaction"', select_sql)

    def test_canonicalize_transactions_prefers_posted_variant(self):
        #R020-T01: Provide duplicate IDs with mixed statuses and verify canonical output keeps the posted variant.
        txns = [
            {"id": "txn_1", "status": "pending", "description": "old"},
            {"id": "txn_1", "status": "posted", "description": "new"},
            {"id": "txn_2", "status": "pending", "description": "x"},
        ]
        out = teller_persist._canonicalize_transactions(txns)
        by_id = {item["id"]: item for item in out}
        self.assertEqual(by_id["txn_1"]["status"], "posted")
        self.assertEqual(len(out), 2)

    def test_reconcile_missing_pending_transactions_deletes_only_missing_ids(self):
        #R025-T01: Persist pending transactions, fetch a reduced set, and verify missing pending rows are deleted.
        #R050-T01: Reconcile pending transaction cleanup SQL with non-empty fetched IDs and verify delete statement targets `teller."transaction"`.
        session = MagicMock()
        session.execute.return_value.fetchall.return_value = [("txn_old",), ("txn_older",)]
        deleted = teller_persist._reconcile_missing_pending_transactions(session, "acc_1", ["txn_keep"])
        sql = str(session.execute.call_args.args[0])
        self.assertIn('DELETE FROM teller."transaction"', sql)
        self.assertIn("transaction_id NOT IN", sql)
        self.assertEqual(deleted, ["txn_old", "txn_older"])

    @patch("teller.teller_persist._exec")
    def test_reconcile_with_empty_fetched_ids_skips_deletion(self, exec_mock):
        #R025-T02: Pass empty fetched IDs and verify all pending transactions for the account are removed.
        #R050-T02: Reconcile pending transaction cleanup SQL with empty fetched IDs and verify delete statement targets `teller."transaction"`.
        deleted = teller_persist._reconcile_missing_pending_transactions(MagicMock(), "acc_1", [])
        self.assertEqual(deleted, [])
        exec_mock.assert_not_called()

    @patch("teller.teller_persist._exec")
    def test_prune_unreferenced_transaction_relations_reports_counts(self, exec_mock):
        #R030-T01: Delete transactions that leave relation rows orphaned and verify orphan pruning removes only unreferenced rows.
        #R055-T01: Run orphan-prune helper and verify generated DELETE SQL does not alias the target table.
        exec_mock.side_effect = [
            _Result(many=[(1,), (2,)]),
            _Result(many=[(3,)]),
            _Result(many=[]),
        ]
        pruned = teller_persist._prune_unreferenced_transaction_relations(MagicMock())
        first_delete_sql = str(exec_mock.call_args_list[0].args[1])
        self.assertIn("DELETE FROM teller.transaction_links", first_delete_sql)
        self.assertNotIn("DELETE FROM teller.transaction_links tl", first_delete_sql)
        self.assertEqual(
            pruned,
            {
                "transaction_links": 2,
                "transaction_details": 1,
                "transaction_details_counterparty": 0,
            },
        )

    @patch("teller.teller_persist._upsert_account_balances_links", return_value=200)
    @patch("teller.teller_persist._exec")
    def test_upsert_account_balances_insert_path_casts_decimals(self, exec_mock, upsert_links):
        #R035-T01: Persist balances for an account and verify insert path writes links and balances.
        exec_mock.return_value = _Result(one=None)
        bal_payload = {
            "account_id": "acc_1",
            "ledger": "101.50",
            "available": "90.25",
            "links": {"self": "s", "account": "a"},
        }
        session = MagicMock()
        teller_persist._upsert_account_balances(session, bal_payload)
        sql = str(exec_mock.call_args_list[-1].args[1])
        params = exec_mock.call_args_list[-1].args[2]
        self.assertIn("INSERT INTO teller.account_balances", sql)
        self.assertEqual(params["ledger"], Decimal("101.50"))
        self.assertEqual(params["available"], Decimal("90.25"))
        upsert_links.assert_called_once_with(session, bal_payload["links"], None)

    @patch("teller.teller_persist._upsert_account_balances_links", return_value=200)
    @patch("teller.teller_persist._exec")
    def test_upsert_account_balances_update_path_refreshes_timestamp(self, exec_mock, _upsert_links):
        #R035-T02: Re-persist with updated balances and verify update path and timestamp refresh.
        exec_mock.return_value = _Result(one=(99, 77))
        bal_payload = {"account_id": "acc_1", "ledger": "5", "available": "2", "links": {"self": "s", "account": "a"}}
        teller_persist._upsert_account_balances(MagicMock(), bal_payload)
        sql = str(exec_mock.call_args_list[-1].args[1])
        self.assertIn("updated_at = CURRENT_TIMESTAMP", sql)

    @patch("teller.teller_persist.log")
    @patch("teller.teller_persist._prune_unreferenced_transaction_relations", return_value={"transaction_links": 0, "transaction_details": 0, "transaction_details_counterparty": 0})
    @patch("teller.teller_persist._reconcile_missing_pending_transactions", return_value=[])
    @patch("teller.teller_persist._upsert_transaction")
    @patch("teller.teller_persist._canonicalize_transactions")
    @patch("teller.teller_persist._upsert_account_balances")
    @patch("teller.teller_persist._upsert_account_identity")
    @patch("teller.teller_persist._upsert_identity", return_value=55)
    @patch("teller.teller_persist._upsert_account")
    def test_persist_all_orchestrates_domains_and_commits_once(self, upsert_account, upsert_identity, upsert_account_identity, upsert_balances, canonicalize, upsert_transaction, reconcile_missing, _prune, _log):
        #R040-T01: Run `persist_all` with representative payloads and verify all data domains are persisted and committed.
        canonicalize.return_value = [{"id": "txn_1"}]
        session = _Session(_Result())
        raw_identities = [{"account": {"id": "acc_1"}, "owners": [{"type": "person"}]}]
        raw_transactions_by_account = {"acc_1": [{"id": "txn_1", "status": "posted"}]}
        raw_balances_by_account = {"acc_1": {"account_id": "acc_1", "links": {}}}

        teller_persist.persist_all(session, raw_identities, raw_transactions_by_account, raw_balances_by_account)

        upsert_account.assert_called_once_with(session, {"id": "acc_1"})
        upsert_identity.assert_called_once()
        upsert_account_identity.assert_called_once_with(session, "acc_1", 55)
        upsert_balances.assert_called_once_with(session, raw_balances_by_account["acc_1"])
        canonicalize.assert_called_once()
        upsert_transaction.assert_called_once_with(session, {"id": "txn_1"})
        reconcile_missing.assert_called_once_with(session, "acc_1", ["txn_1"])
        self.assertEqual(session.commits, 1)

    @patch("teller.teller_persist._prune_unreferenced_transaction_relations", return_value={"transaction_links": 0, "transaction_details": 0, "transaction_details_counterparty": 0})
    @patch("teller.teller_persist._reconcile_missing_pending_transactions", return_value=[])
    @patch("teller.teller_persist._upsert_transaction")
    @patch("teller.teller_persist._canonicalize_transactions", return_value=[])
    @patch("teller.teller_persist._upsert_account_balances")
    @patch("teller.teller_persist._upsert_account_identity")
    @patch("teller.teller_persist._upsert_identity", return_value=66)
    @patch("teller.teller_persist._upsert_account")
    def test_persist_all_allows_omitting_balances(self, _upsert_account, _upsert_identity, _upsert_account_identity, upsert_balances, _canonicalize, _upsert_transaction, reconcile, _prune):
        #R040-T02: Verify `raw_balances_by_account` is optional and does not block persistence when omitted.
        session = _Session(_Result())
        teller_persist.persist_all(
            session,
            raw_identities=[{"account": {"id": "acc_1"}, "owners": [{"type": "person"}]}],
            raw_transactions_by_account={"acc_1": [{"id": "txn_1", "status": "posted"}]},
            raw_balances_by_account=None,
        )
        upsert_balances.assert_not_called()
        reconcile.assert_not_called()
        self.assertEqual(session.commits, 1)

    @patch("teller.teller_persist._upsert_account", side_effect=RuntimeError("boom"))
    def test_persist_all_rolls_back_when_any_step_fails(self, _upsert_account):
        #R040-T03: Verify persist_all rolls back when any orchestration step fails.
        session = _Session(_Result())
        with self.assertRaises(RuntimeError):
            teller_persist.persist_all(
                session,
                raw_identities=[{"account": {"id": "acc_1"}, "owners": []}],
                raw_transactions_by_account={},
                raw_balances_by_account={},
            )
        self.assertEqual(session.commits, 0)
        self.assertEqual(session.rollbacks, 1)


if __name__ == "__main__":
    unittest.main()
