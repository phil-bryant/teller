import unittest

from teller.teller_base import Base


class TellerBaseTests(unittest.TestCase):
    def test_base_has_registry(self):
        self.assertIsNotNone(Base.registry)

    def test_registry_contains_metadata(self):
        self.assertIsNotNone(Base.metadata)


if __name__ == "__main__":
    unittest.main()
import unittest



class TellerBaseTests(unittest.TestCase):
    def test_base_has_registry(self):
        self.assertIsNotNone(Base.registry)

    def test_registry_contains_metadata(self):
        self.assertIsNotNone(Base.metadata)


if __name__ == "__main__":
    unittest.main()
import unittest

from sqlalchemy.orm import Mapped, mapped_column



class TellerBaseTests(unittest.TestCase):
    def test_base_exposes_registry_and_metadata(self):
        self.assertTrue(hasattr(Base, "registry"))
        self.assertIs(Base.registry.metadata, Base.metadata)

    def test_declarative_subclass_binds_to_base_registry(self):
        class ExampleRecord(Base):
            __tablename__ = "example_record"
            id: Mapped[int] = mapped_column(primary_key=True)

        self.assertEqual(ExampleRecord.__tablename__, "example_record")
        self.assertIs(ExampleRecord.metadata, Base.metadata)
        self.assertIsNotNone(ExampleRecord.__table__.c.id)


if __name__ == "__main__":
    unittest.main()
