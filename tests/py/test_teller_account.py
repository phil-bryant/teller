from types import SimpleNamespace
import unittest
from unittest.mock import patch

from teller.teller_account import TellerAccount


class TellerAccountTests(unittest.TestCase):
    @patch("teller.teller_account.TellerAccountDetails")
    def test_get_details_reads_api_client_and_stores_result(self, details_cls):
        #R600-T01: Verify `get_details()` reads API client response and stores hydrated details.
        account = SimpleNamespace(
            links=SimpleNamespace(details="/accounts/acc_1/details"),
            _api_client=SimpleNamespace(get=lambda path: {"path": path}),
        )
        details_obj = SimpleNamespace(kind="details")
        details_cls.return_value = details_obj

        result = TellerAccount.get_details(account)

        details_cls.assert_called_once_with({"path": "/accounts/acc_1/details"})
        self.assertIs(result, details_obj)
        self.assertIs(account.details, details_obj)


if __name__ == "__main__":
    unittest.main()
