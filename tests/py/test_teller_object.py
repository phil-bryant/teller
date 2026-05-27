import unittest
from dataclasses import dataclass, field
from datetime import timezone
from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from teller.teller_account_identities import TellerAccountIdentities  # noqa: F401
from teller.teller_object import TellerObject


@dataclass(init=False)
class TellerTransactionDetails(TellerObject):
    __table_args__ = {"schema": "teller", "extend_existing": True}
    transaction_details_id: Mapped[int] = mapped_column(primary_key=True, default=1)
    aliased_name: Mapped[str] = mapped_column(default="", info={"api_name": "api_name"})
    amount: int = 0
    debug_label: str = field(default="", metadata={"__str__": True})
    hidden_label: str = field(default="", metadata={"__str__": False})


class TellerObjectTests(unittest.TestCase):
    def test_timestamp_mixin_fields_exist_with_configured_defaults(self):
        #R001-T01
        #R001-T02
        row = TellerTransactionDetails()
        self.assertTrue(hasattr(row, "created_at"))
        self.assertTrue(hasattr(row, "updated_at"))
        created_default = TellerTransactionDetails.__table__.c.created_at.default
        updated_default = TellerTransactionDetails.__table__.c.updated_at.default
        updated_onupdate = TellerTransactionDetails.__table__.c.updated_at.onupdate
        self.assertIsNotNone(created_default)
        self.assertIsNotNone(updated_default)
        self.assertIsNotNone(updated_onupdate)
        created_value = created_default.arg() if callable(created_default.arg) else created_default.arg
        updated_value = updated_default.arg() if callable(updated_default.arg) else updated_default.arg
        onupdate_value = updated_onupdate.arg() if callable(updated_onupdate.arg) else updated_onupdate.arg
        self.assertIsNotNone(created_value.tzinfo)
        self.assertIsNotNone(updated_value.tzinfo)
        self.assertIsNotNone(onupdate_value.tzinfo)
        self.assertEqual(created_value.tzinfo, timezone.utc)
        self.assertEqual(updated_value.tzinfo, timezone.utc)
        self.assertEqual(onupdate_value.tzinfo, timezone.utc)
        self.assertEqual(TellerTransactionDetails.__table__.schema, "teller")

    def test_tablename_is_derived_from_class_name(self):
        #R005-T01
        self.assertEqual(TellerTransactionDetails.__tablename__, "transaction_details")

    def test_set_api_client_sets_class_shared_reference(self):
        #R010-T01
        fake_client = object()
        TellerTransactionDetails.set_api_client(fake_client)
        row = TellerTransactionDetails()
        self.assertIs(row._api_client, fake_client)

    def test_init_with_api_payload_hydrates_mapped_fields(self):
        #R015-T01
        #R020-T01
        #R020-T02
        #R025-T01
        row = TellerTransactionDetails(
            {
                "api_name": "merchant",
                "amount": "42",
                "debug_label": "visible",
                "unknown": "ignored",
            }
        )
        self.assertEqual(row.aliased_name, "merchant")
        self.assertEqual(row.amount, 42)
        self.assertEqual(row.debug_label, "visible")
        self.assertFalse(hasattr(row, "unknown"))

    def test_init_without_payload_skips_hydration(self):
        #R015-T02
        row = TellerTransactionDetails()
        self.assertEqual(row.amount, 0)
        self.assertFalse(hasattr(row, "_api_data"))

    def test_unpack_annotation_identifies_list_inner_type(self):
        row = TellerTransactionDetails()
        target, is_list = row._unpack_annotation(Optional[list[int]])
        self.assertIs(target, int)
        self.assertTrue(is_list)

    def test_hydration_falls_back_to_raw_value_when_cast_fails(self):
        #R025-T02
        row = TellerTransactionDetails({"amount": "not-an-int"})
        self.assertEqual(row.amount, "not-an-int")

    def test_str_includes_only_marked_fields_plus_api_data(self):
        #R030-T01
        row = TellerTransactionDetails({"debug_label": "only_this", "hidden_label": "skip_this"})
        text = str(row)
        field_segment, _, api_segment = text.partition("):_api_data=")
        self.assertIn("only_this", field_segment)
        self.assertNotIn("skip_this", field_segment)
        self.assertIn("skip_this", api_segment)
        self.assertIn("_api_data=", text)


if __name__ == "__main__":
    unittest.main()
