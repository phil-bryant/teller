import unittest

from teller.teller_institution import TellerInstitution


class TellerInstitutionTests(unittest.TestCase):
    def test_institution_model_maps_id_and_unique_name_columns(self):
        #R600-T01: Verify institution model maps id/name columns with expected metadata.
        table = TellerInstitution.__table__
        self.assertIn("institution_id", table.c)
        self.assertIn("name", table.c)
        self.assertTrue(table.c.name.unique)


if __name__ == "__main__":
    unittest.main()
