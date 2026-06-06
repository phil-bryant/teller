import unittest

from sqlalchemy.orm import Mapped, mapped_column

from teller.teller_base import Base


class TellerBaseTests(unittest.TestCase):
    def test_base_exposes_registry_and_metadata(self):
        #R600-T01: Verify Base exposes shared registry metadata.
        self.assertTrue(hasattr(Base, "registry"))
        self.assertIs(Base.registry.metadata, Base.metadata)

    def test_declarative_subclass_binds_to_base_registry(self):
        #R605-T01: Verify declarative subclass binds to shared base registry.
        # This probe model registers on the shared, module-global Base.metadata.
        # Tear it back down so the test stays idempotent when the configured suite
        # is executed more than once within a single process -- e.g. mutmut's
        # prepare phase runs coverage gathering and stats collection back-to-back
        # in-process. Without cleanup the second run re-defines the table and
        # raises "Table 'example_record' is already defined for this MetaData
        # instance", which made teller's mutation lane skip instead of producing
        # verdicts.
        class ExampleRecord(Base):
            __tablename__ = "example_record"
            id: Mapped[int] = mapped_column(primary_key=True)

        self.addCleanup(Base.metadata.remove, ExampleRecord.__table__)
        self.addCleanup(Base.registry._dispose_cls, ExampleRecord)

        self.assertEqual(ExampleRecord.__tablename__, "example_record")
        self.assertIs(ExampleRecord.metadata, Base.metadata)
        self.assertIsNotNone(ExampleRecord.__table__.c.id)


if __name__ == "__main__":
    unittest.main()
