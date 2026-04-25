import unittest
from datetime import datetime, timezone
from fastapi import HTTPException
from pydantic import ValidationError
from types import SimpleNamespace
from unittest.mock import patch

from teller.teller_classification_api import (
    _category_params,
    _display_label,
    _write_category,
    _write_one,
    create_app,
    CategoryMutation,
    ClassificationMutation,
    ClassificationBatchRequest,
)


class _Result:
    def __init__(self, row=None, rows=None, scalar=None):
        self._row = row
        self._rows = rows or []
        self._scalar = scalar

    def fetchone(self):
        return self._row

    def mappings(self):
        return self

    def all(self):
        return self._rows

    def scalar_one(self):
        return self._scalar


class _FakeSession:
    def __init__(self, rows):
        self.rows = list(rows)
        self.calls = []
        self.commits = 0

    def execute(self, sql, params=None):
        self.calls.append((str(sql), params or {}))
        return self.rows.pop(0) if self.rows else _Result()

    def commit(self):
        self.commits += 1


class _SessionContext:
    def __init__(self, session):
        self.session = session

    def __enter__(self):
        return self.session

    def __exit__(self, exc_type, exc, tb):
        return False


class ClassificationApiTests(unittest.TestCase):
    def _route_endpoint(self, app, path, method):
        for route in app.routes:
            if getattr(route, "path", None) == path and method in getattr(route, "methods", set()):
                return route.endpoint
        raise AssertionError(f"route not found: {method} {path}")

    def test_create_app_registers_required_routes(self):
        #R001
        app = create_app()
        route_paths = {route.path for route in app.routes}
        self.assertIn("/health", route_paths)
        self.assertIn("/v1/categories", route_paths)
        self.assertIn("/v1/categories/{nys_snw_category_id:int}", route_paths)
        self.assertIn("/v1/categories/counts", route_paths)
        self.assertIn("/v1/transactions", route_paths)
        self.assertIn("/v1/transactions/{transaction_id}/classification", route_paths)
        self.assertIn("/v1/transactions/classifications", route_paths)

    def test_display_label_joins_hierarchy(self):
        #R005
        row = {"level_1_name": "EXPENSES", "level_2_name": "Food", "level_3": "1.", "level_4": None, "categorization": "Groceries"}
        self.assertEqual(_display_label(row), "EXPENSES > Food > 1. > Groceries")

    def test_display_label_skips_empty_segments(self):
        row = {"level_1_name": "EXPENSES", "level_2_name": "", "level_3": None, "level_4": "Sub", "categorization": "Groceries"}
        self.assertEqual(_display_label(row), "EXPENSES > Sub > Groceries")

    def test_category_params_normalizes_whitespace(self):
        params = _category_params(
            CategoryMutation(
                level_1=" II. ",
                level_1_name="",
                level_2=None,
                level_2_name="  Housing  ",
                level_3=" ",
                level_4="A.",
                categorization=" Rent ",
                applicability="N/A",
            )
        )
        self.assertEqual(params["level_1"], "II.")
        self.assertIsNone(params["level_1_name"])
        self.assertEqual(params["level_2_name"], "Housing")
        self.assertIsNone(params["level_3"])
        self.assertEqual(params["categorization"], "Rent")

    def test_write_category_inserts_and_returns_display_label(self):
        session = _FakeSession(
            rows=[
                _Result(row=(42,)),
                _Result(
                    row={
                        "nys_snw_category_id": 42,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": None,
                        "level_2_name": None,
                        "level_3": None,
                        "level_4": None,
                        "categorization": "Rent",
                        "applicability": None,
                    }
                ),
            ]
        )
        response = _write_category(session, CategoryMutation(level_1="II.", level_1_name="EXPENSES", categorization="Rent"))
        self.assertEqual(response.nys_snw_category_id, 42)
        self.assertEqual(response.display_label, "EXPENSES > Rent")
        self.assertEqual(session.commits, 1)

    def test_write_category_updates_existing_row(self):
        session = _FakeSession(
            rows=[
                _Result(row=(1,)),
                _Result(),
                _Result(
                    row={
                        "nys_snw_category_id": 9,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": "(a)",
                        "level_2_name": "Housing",
                        "level_3": "2.",
                        "level_4": None,
                        "categorization": "Mortgage",
                        "applicability": None,
                    }
                ),
            ]
        )
        response = _write_category(session, CategoryMutation(categorization="Mortgage"), category_id=9)
        self.assertEqual(response.nys_snw_category_id, 9)
        self.assertEqual(response.display_label, "EXPENSES > Housing > 2. > Mortgage")
        self.assertEqual(session.commits, 1)

    def test_write_one_inserts_when_missing_existing_mapping(self):
        ts = datetime.now(tz=timezone.utc)
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(row=(1,)), _Result(row=None), _Result(row=(ts,))])
        response = _write_one(session, "txn_1", 12)
        self.assertEqual(response.transaction_id, "txn_1")
        self.assertEqual(response.nys_snw_category_id, 12)
        self.assertEqual(session.commits, 1)

    def test_write_one_updates_when_existing_mapping_present(self):
        ts = datetime.now(tz=timezone.utc)
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(row=(1,)), _Result(row=(ts,))])
        response = _write_one(session, "txn_2", 33)
        self.assertEqual(response.nys_snw_category_id, 33)
        self.assertEqual(session.commits, 1)
        self.assertIn("status = 'posted'", session.calls[0][0])

    def test_write_one_deletes_mapping_when_category_is_none(self):
        session = _FakeSession(rows=[_Result(row=(1,))])
        response = _write_one(session, "txn_3", None)
        self.assertIsNone(response.nys_snw_category_id)
        self.assertEqual(session.commits, 1)

    def test_write_one_raises_on_unknown_transaction(self):
        #R025
        session = _FakeSession(rows=[_Result(row=None)])
        with self.assertRaises(HTTPException) as ctx:
            _write_one(session, "txn_missing", 12)
        self.assertEqual(ctx.exception.status_code, 404)

    def test_write_one_raises_on_unknown_category(self):
        #R025
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(row=None)])
        with self.assertRaises(HTTPException) as ctx:
            _write_one(session, "txn_1", 999)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("Unknown nys_snw_category_id", ctx.exception.detail)

    @patch("teller.teller_classification_api.get_session")
    def test_categories_endpoint_returns_display_labels(self, get_session_mock):
        #R010
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories", "GET")
        session = _FakeSession(
            rows=[
                _Result(
                    rows=[
                        {
                            "nys_snw_category_id": 1,
                            "level_1": "A",
                            "level_1_name": "EXPENSES",
                            "level_2": None,
                            "level_2_name": None,
                            "level_3": None,
                            "level_4": None,
                            "categorization": "Groceries",
                            "applicability": None,
                        }
                    ]
                )
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint()
        self.assertEqual(body[0].display_label, "EXPENSES > Groceries")

    @patch("teller.teller_classification_api.get_session")
    def test_category_counts_includes_zero_assignment_categories(self, get_session_mock):
        #R015
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/counts", "GET")
        session = _FakeSession(
            rows=[
                _Result(
                    rows=[
                        {
                            "nys_snw_category_id": 1,
                            "level_1": "A",
                            "level_1_name": "EXPENSES",
                            "level_2": None,
                            "level_2_name": None,
                            "level_3": None,
                            "level_4": None,
                            "categorization": "Food",
                            "assigned_transactions": 2,
                        },
                        {
                            "nys_snw_category_id": 2,
                            "level_1": "A",
                            "level_1_name": "EXPENSES",
                            "level_2": None,
                            "level_2_name": None,
                            "level_3": None,
                            "level_4": None,
                            "categorization": "Other",
                            "assigned_transactions": 0,
                        },
                    ]
                )
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint()
        self.assertEqual(body[1].assigned_transactions, 0)

    @patch("teller.teller_classification_api.get_session")
    def test_create_category_endpoint_returns_saved_row(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories", "POST")
        session = _FakeSession(
            rows=[
                _Result(row=(55,)),
                _Result(
                    row={
                        "nys_snw_category_id": 55,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": None,
                        "level_2_name": None,
                        "level_3": None,
                        "level_4": None,
                        "categorization": "Pets",
                        "applicability": None,
                    }
                ),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint(CategoryMutation(level_1_name="EXPENSES", categorization="Pets"))
        self.assertEqual(body.nys_snw_category_id, 55)
        self.assertEqual(body.display_label, "EXPENSES > Pets")

    @patch("teller.teller_classification_api.get_session")
    def test_update_category_endpoint_404s_for_unknown_id(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "PUT")
        session = _FakeSession(rows=[_Result(row=None)])
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(nys_snw_category_id=999, body=CategoryMutation(categorization="X"))
        self.assertEqual(ctx.exception.status_code, 404)

    @patch("teller.teller_classification_api.get_session")
    def test_delete_category_rejects_assigned_categories(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "DELETE")
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(scalar=2)])
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(nys_snw_category_id=4)
        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("still reference", ctx.exception.detail)

    @patch("teller.teller_classification_api.get_session")
    def test_delete_category_succeeds_when_unassigned(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "DELETE")
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(scalar=0), _Result()])
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint(nys_snw_category_id=4)
        self.assertEqual(body.nys_snw_category_id, 4)
        self.assertTrue(body.deleted)
        self.assertEqual(session.commits, 1)

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_endpoint_applies_filters_and_returns_total(self, get_session_mock):
        #R020
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(
            rows=[
                _Result(scalar=1),
                _Result(
                    rows=[
                        {
                            "transaction_id": "txn_1",
                            "account_id": "acc_1",
                            "institution_id": "ins_1",
                            "account_last_four": "1234",
                            "date": "2026-01-01",
                            "amount": "5.00",
                            "description": "Coffee",
                            "status": "posted",
                            "transaction_type_code": "card_payment",
                            "teller_category": "FOOD",
                            "nys_snw_category_id": None,
                            "level_1": None,
                            "level_1_name": None,
                            "level_2": None,
                            "level_2_name": None,
                            "level_3": None,
                            "level_4": None,
                            "categorization": None,
                        }
                    ]
                ),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            query_params={
                "search": "cof",
                "status": "posted",
                "only_unclassified": "true",
                "limit": "10",
                "offset": "2",
            }
        )
        body = endpoint(request=request, search="cof", status="posted", only_unclassified=True, limit=10, offset=2)
        self.assertEqual(body.total, 1)
        self.assertEqual(len(body.items), 1)
        count_sql, count_params = session.calls[0]
        list_sql, list_params = session.calls[1]
        self.assertIn("tt.status = 'posted'", count_sql)
        self.assertIn("tt.status::text = :status", count_sql)
        self.assertIn("ILIKE :search_pattern", count_sql)
        self.assertIn("m.nys_snw_category_id IS NULL", count_sql)
        self.assertIn("ORDER BY tt.date DESC, tt.transaction_id DESC", list_sql)
        self.assertEqual(count_params["search"], "cof")
        self.assertEqual(count_params["search_pattern"], "%cof%")
        self.assertTrue(count_params["only_unclassified"])
        self.assertEqual(list_params["limit"], 10)
        self.assertEqual(list_params["offset"], 2)

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_single_classification_rejects_path_payload_mismatch(self, get_session_mock, write_one_mock):
        #R030
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions/{transaction_id}/classification", "PUT")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        endpoint(transaction_id="txn_path", body=ClassificationMutation(transaction_id="txn_body", nys_snw_category_id=12))
        write_one_mock.assert_called_once()
        call_args, _ = write_one_mock.call_args
        self.assertEqual(call_args[1], "txn_path")
        self.assertEqual(call_args[2], 12)

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_requires_non_empty_updates(self, get_session_mock, write_one_mock):
        #R035
        with self.assertRaises(ValidationError):
            ClassificationBatchRequest(updates=[])
        write_one_mock.assert_not_called()

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_returns_one_row_per_input(self, get_session_mock, write_one_mock):
        #R035
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions/classifications", "POST")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        write_one_mock.side_effect = [
            {"transaction_id": "txn_1", "nys_snw_category_id": 1, "type": "user", "updated_at": datetime.now(timezone.utc)},
            {"transaction_id": "txn_2", "nys_snw_category_id": None, "type": "user", "updated_at": datetime.now(timezone.utc)},
        ]
        response = endpoint(
            body=SimpleNamespace(
                updates=[
                    SimpleNamespace(transaction_id="txn_1", nys_snw_category_id=1),
                    SimpleNamespace(transaction_id="txn_2", nys_snw_category_id=None),
                ]
            )
        )
        self.assertEqual(len(response), 2)
        self.assertEqual(write_one_mock.call_count, 2)

if __name__ == "__main__":
    unittest.main()
