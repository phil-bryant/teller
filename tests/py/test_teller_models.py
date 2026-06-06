from types import SimpleNamespace
import unittest
from unittest.mock import patch

from teller.teller_account import TellerAccount


class TellerAccountModelTests(unittest.TestCase):
    #R600: Verify institution_name returns empty value when institution is missing.
    def test_institution_name_returns_empty_string_without_institution(self):
        account = SimpleNamespace(institution=None)
        self.assertEqual(TellerAccount.institution_name(account), "")

    #R600: Verify institution_name returns nested institution display name.
    def test_institution_name_returns_nested_name(self):
        account = SimpleNamespace(institution=SimpleNamespace(name="Bank Name"))
        self.assertEqual(TellerAccount.institution_name(account), "Bank Name")

    @patch("teller.teller_account.TellerAccountDetails")
    #R600: Verify get_details hydrates and stores account details payload.
    def test_get_details_reads_api_client_and_stores_result(self, details_cls):
        account = SimpleNamespace(
            links=SimpleNamespace(details="/accounts/acc_1/details"),
            _api_client=SimpleNamespace(get=lambda path: {"path": path}),
        )
        details_instance = SimpleNamespace(kind="details")
        details_cls.return_value = details_instance

        result = TellerAccount.get_details(account)

        details_cls.assert_called_once_with({"path": "/accounts/acc_1/details"})
        self.assertIs(result, details_instance)
        self.assertIs(account.details, details_instance)

    @patch("teller.teller_account.TellerTransaction")
    #R600: Verify get_transactions forwards count filter to API client.
    def test_get_transactions_uses_count_query_when_provided(self, transaction_cls):
        account = SimpleNamespace(
            links=SimpleNamespace(transactions="/accounts/acc_1/transactions"),
            _api_client=SimpleNamespace(
                get=lambda path, params: [
                    {"id": "txn_1", "path": path, "params": params},
                ]
            ),
        )
        tx_instance = SimpleNamespace(id="txn_1")
        transaction_cls.return_value = tx_instance

        result = TellerAccount.get_transactions(account, count=5)

        transaction_cls.assert_called_once_with(
            {"id": "txn_1", "path": "/accounts/acc_1/transactions", "params": {"count": 5}}
        )
        self.assertEqual(result, [tx_instance])


if __name__ == "__main__":
    unittest.main()
