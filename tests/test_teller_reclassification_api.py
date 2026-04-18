import unittest
from datetime import datetime, timezone
from fastapi import HTTPException
from teller.teller_reclassification_api import _display_label, _write_one


class _Result:
    def __init__(self, row): self._row = row
    def fetchone(self): return self._row


class _FakeSession:
    def __init__(self, rows):
        self.rows = list(rows)
        self.calls = []
        self.commits = 0

    def execute(self, sql, params=None):
        self.calls.append((str(sql), params or {}))
        return _Result(self.rows.pop(0) if self.rows else None)

    def commit(self):
        self.commits += 1


class ReclassificationApiTests(unittest.TestCase):
    def test_display_label_joins_hierarchy(self):
        row = {"level_1_name": "EXPENSES", "level_2_name": "Food", "level_3": "1.", "level_4": None, "categorization": "Groceries"}
        self.assertEqual(_display_label(row), "EXPENSES > Food > 1. > Groceries")

    def test_write_one_inserts_when_missing_existing_mapping(self):
        ts = datetime.now(tz=timezone.utc)
        session = _FakeSession(rows=[(1,), (1,), None, (ts,)])
        response = _write_one(session, "txn_1", 12)
        self.assertEqual(response.transaction_id, "txn_1")
        self.assertEqual(response.nys_snw_category_id, 12)
        self.assertEqual(session.commits, 1)

    def test_write_one_updates_when_existing_mapping_present(self):
        ts = datetime.now(tz=timezone.utc)
        session = _FakeSession(rows=[(1,), (1,), (ts,)])
        response = _write_one(session, "txn_2", 33)
        self.assertEqual(response.nys_snw_category_id, 33)
        self.assertEqual(session.commits, 1)

    def test_write_one_deletes_mapping_when_category_is_none(self):
        session = _FakeSession(rows=[(1,)])
        response = _write_one(session, "txn_3", None)
        self.assertIsNone(response.nys_snw_category_id)
        self.assertEqual(session.commits, 1)

    def test_write_one_raises_on_unknown_transaction(self):
        session = _FakeSession(rows=[None])
        with self.assertRaises(HTTPException) as ctx:
            _write_one(session, "txn_missing", 12)
        self.assertEqual(ctx.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
