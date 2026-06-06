import unittest
from dataclasses import dataclass, field
from datetime import timezone
from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from teller.teller_account_identities import TellerAccountIdentities  # noqa: F401
from teller.teller_object import TellerObject


#R001: Resolve SQLAlchemy default callables for deterministic assertions.
def _resolve_column_default(default_obj):
    arg = default_obj.arg
    if not callable(arg):
        return arg
    try:
        return arg()
    except TypeError:
        return arg(None)


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
        #R001-T01: Instantiate a concrete subclass and verify `created_at`/`updated_at` default values are assigned.
        #R001-T02: Verify generated tables for subclasses target the `teller` schema.
        row = TellerTransactionDetails()
        self.assertTrue(hasattr(row, "created_at"))
        self.assertTrue(hasattr(row, "updated_at"))
        created_default = TellerTransactionDetails.__table__.c.created_at.default
        updated_default = TellerTransactionDetails.__table__.c.updated_at.default
        updated_onupdate = TellerTransactionDetails.__table__.c.updated_at.onupdate
        self.assertIsNotNone(created_default)
        self.assertIsNotNone(updated_default)
        self.assertIsNotNone(updated_onupdate)
        created_value = _resolve_column_default(created_default)
        updated_value = _resolve_column_default(updated_default)
        onupdate_value = _resolve_column_default(updated_onupdate)
        self.assertIsNotNone(created_value.tzinfo)
        self.assertIsNotNone(updated_value.tzinfo)
        self.assertIsNotNone(onupdate_value.tzinfo)
        self.assertEqual(created_value.tzinfo, timezone.utc)
        self.assertEqual(updated_value.tzinfo, timezone.utc)
        self.assertEqual(onupdate_value.tzinfo, timezone.utc)
        self.assertEqual(TellerTransactionDetails.__table__.schema, "teller")

    def test_tablename_is_derived_from_class_name(self):
        #R005-T01: Define a concrete class such as `TellerTransactionDetails` and verify table name resolves to `transaction_details`.
        self.assertEqual(TellerTransactionDetails.__tablename__, "transaction_details")

    def test_set_api_client_sets_class_shared_reference(self):
        #R010-T01: Call `set_api_client` on a subclass and verify subsequent instances can access the shared client reference.
        fake_client = object()
        TellerTransactionDetails.set_api_client(fake_client)
        row = TellerTransactionDetails()
        self.assertIs(row._api_client, fake_client)

    def test_init_with_api_payload_hydrates_mapped_fields(self):
        #R015-T01: Instantiate with API payload and verify mapped fields are populated.
        #R020-T01: Add a field with `api_name` metadata and verify hydration reads the aliased payload key.
        #R020-T02: Verify unmapped payload keys are ignored.
        #R025-T01: Hydrate list-typed and scalar-typed fields and verify converted Python types.
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
        #R015-T02: Instantiate without API payload and verify no hydration pass runs.
        row = TellerTransactionDetails()
        self.assertEqual(row.amount, 0)
        self.assertFalse(hasattr(row, "_api_data"))

    def test_unpack_annotation_identifies_list_inner_type(self):
        #R025-T03: Verify annotation unpacking identifies list inner type hints.
        row = TellerTransactionDetails()
        target, is_list = row._unpack_annotation(Optional[list[int]])
        self.assertIs(target, int)
        self.assertTrue(is_list)

    def test_hydration_falls_back_to_raw_value_when_cast_fails(self):
        #R025-T02: Provide non-castable input and verify raw value fallback is retained.
        row = TellerTransactionDetails({"amount": "not-an-int"})
        self.assertEqual(row.amount, "not-an-int")

    def test_str_includes_only_marked_fields_plus_api_data(self):
        #R030-T01: Mark fields with `__str__` metadata and verify string output includes only marked fields plus `_api_data`.
        row = TellerTransactionDetails({"debug_label": "only_this", "hidden_label": "skip_this"})
        text = str(row)
        field_segment, _, api_segment = text.partition("):_api_data=")
        self.assertIn("only_this", field_segment)
        self.assertNotIn("skip_this", field_segment)
        self.assertIn("skip_this", api_segment)
        self.assertIn("_api_data=", text)


if __name__ == "__main__":
    unittest.main()
