import unittest

from teller.teller_enums import (
    TellerAccountStatus,
    TellerAccountSubtype,
    TellerAccountType,
    TellerIdentityPhoneNumberType,
    TellerTransactionStatus,
)


class TellerEnumsTests(unittest.TestCase):
    def test_account_type_values_are_stable(self):
        #R600-T01: Verify account-type enum values remain stable.
        values = {member.value for member in TellerAccountType}
        self.assertEqual(values, {"depository", "credit"})

    def test_account_subtype_includes_common_bank_products(self):
        #R605-T01: Verify account-subtype enum includes common bank products.
        values = {member.value for member in TellerAccountSubtype}
        self.assertIn("checking", values)
        self.assertIn("savings", values)
        self.assertIn("money_market", values)
        self.assertIn("credit_card", values)

    def test_transaction_status_values_are_posted_and_pending(self):
        #R610-T01: Verify transaction-status enum values are posted/pending.
        values = {member.value for member in TellerTransactionStatus}
        self.assertEqual(values, {"posted", "pending"})

    def test_identity_phone_number_type_preserves_unknown_value(self):
        #R620-T01: Verify phone-number enum preserves unknown sentinel.
        values = {member.value for member in TellerIdentityPhoneNumberType}
        self.assertIn("unknown", values)

    def test_account_status_values_are_open_and_closed(self):
        #R615-T01: Verify account-status enum values are open/closed.
        values = {member.value for member in TellerAccountStatus}
        self.assertEqual(values, {"open", "closed"})


if __name__ == "__main__":
    unittest.main()
