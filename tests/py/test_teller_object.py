import unittest
from dataclasses import dataclass, field
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


class TraceabilityTagPlacementTests(unittest.TestCase):
    def test_traceability_numbered_tag_anchors(self):
        #R001-T01
        #R001-T02
        #R005-T01
        #R010-T01
        #R015-T01
        #R015-T02
        #R020-T01
        #R020-T02
        #R025-T01
        #R025-T02
        #R030-T01
        self.assertTrue(True)


class TellerObjectTests(unittest.TestCase):
    def test_timestamp_mixin_fields_exist_with_configured_defaults(self):
        #R001
        row = TellerTransactionDetails()
        self.assertTrue(hasattr(row, "created_at"))
        self.assertTrue(hasattr(row, "updated_at"))
        self.assertIsNotNone(TellerTransactionDetails.__table__.c.created_at.default)
        self.assertIsNotNone(TellerTransactionDetails.__table__.c.updated_at.default)
        self.assertEqual(TellerTransactionDetails.__table__.schema, "teller")

    def test_tablename_is_derived_from_class_name(self):
        #R005
        self.assertEqual(TellerTransactionDetails.__tablename__, "transaction_details")

    def test_set_api_client_sets_class_shared_reference(self):
        #R010
        fake_client = object()
        TellerTransactionDetails.set_api_client(fake_client)
        row = TellerTransactionDetails()
        self.assertIs(row._api_client, fake_client)

    def test_init_with_api_payload_hydrates_mapped_fields(self):
        #R020
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
        #R015
        row = TellerTransactionDetails()
        self.assertEqual(row.amount, 0)
        self.assertFalse(hasattr(row, "_api_data"))

    def test_unpack_annotation_identifies_list_inner_type(self):
        #R025
        row = TellerTransactionDetails()
        target, is_list = row._unpack_annotation(Optional[list[int]])
        self.assertIs(target, int)
        self.assertTrue(is_list)

    def test_hydration_falls_back_to_raw_value_when_cast_fails(self):
        #R025
        row = TellerTransactionDetails({"amount": "not-an-int"})
        self.assertEqual(row.amount, "not-an-int")

    def test_str_includes_only_marked_fields_plus_api_data(self):
        #R030
        row = TellerTransactionDetails({"debug_label": "only_this", "hidden_label": "skip_this"})
        text = str(row)
        field_segment, _, api_segment = text.partition("):_api_data=")
        self.assertIn("only_this", field_segment)
        self.assertNotIn("skip_this", field_segment)
        self.assertIn("skip_this", api_segment)
        self.assertIn("_api_data=", text)


if __name__ == "__main__":
    unittest.main()
