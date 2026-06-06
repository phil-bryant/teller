import unittest

from teller.teller_transaction import TellerTransaction


class TellerTransactionTests(unittest.TestCase):
    def test_transaction_model_declares_account_relationship_join(self):
        #R600-T01: Verify transaction model declares account relationship join metadata.
        relationship = TellerTransaction.account.property
        self.assertEqual(str(relationship.primaryjoin), "teller.transaction.account_id = teller.account.account_id")
        self.assertEqual(relationship.mapper.class_.__name__, "TellerAccount")


if __name__ == "__main__":
    unittest.main()
