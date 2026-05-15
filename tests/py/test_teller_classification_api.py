import unittest
from datetime import datetime, timezone
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from types import SimpleNamespace
from unittest.mock import patch

from teller.teller_classification_api import (
    _category_params,
    _display_label,
    _transition_match_state,
    _write_category,
    _write_one,
    create_app,
    CategoryCreateMutation,
    CategoryUpdateMutation,
    ClassificationMutation,
    SingleClassificationMutation,
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


class _IntegrityErrorSession(_FakeSession):
    def execute(self, sql, params=None):
        raise IntegrityError(statement=str(sql), params=params or {}, orig=Exception("duplicate key"))


class _SessionContext:
    def __init__(self, session):
        self.session = session

    def __enter__(self):
        return self.session

    def __exit__(self, exc_type, exc, tb):
        return False


class ClassificationApiTests(unittest.TestCase):
    def setUp(self):
        self._token_patch = patch(
            "teller.teller_classification_api._configured_write_token",
            return_value="test-write-token",
        )
        self._token_patch.start()

    def tearDown(self):
        self._token_patch.stop()

    def _route_endpoint(self, app, path, method):
        for route in app.routes:
            if getattr(route, "path", None) == path and method in getattr(route, "methods", set()):
                return route.endpoint
        raise AssertionError(f"route not found: {method} {path}")

    def _authorized_request(self):
        return SimpleNamespace(headers={"x-teller-write-token": "test-write-token"})

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
            CategoryCreateMutation(
                level_1=" II. ",
                level_1_name="",
                level_2_name="  Housing  ",
                level_3=" ",
                level_4="A.",
                categorization=" Rent ",
                applicability="N/A",
            ),
            include_unset=True,
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
                        "is_seed": False,
                    }
                ),
            ]
        )
        response = _write_category(
            session,
            CategoryCreateMutation(level_1="II.", level_1_name="EXPENSES", categorization="Rent"),
        )
        self.assertEqual(response.nys_snw_category_id, 42)
        self.assertEqual(response.display_label, "EXPENSES > Rent")
        self.assertEqual(session.commits, 1)

    def test_write_category_updates_existing_row(self):
        session = _FakeSession(
            rows=[
                _Result(row=(1,)),
                _Result(
                    row={
                        "nys_snw_category_id": 9,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": "(a)",
                        "level_2_name": "Housing",
                        "level_3": "2.",
                        "level_4": None,
                        "categorization": "Rent",
                        "applicability": None,
                        "is_seed": False,
                    }
                ),
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
                        "is_seed": False,
                    }
                ),
            ]
        )
        response = _write_category(session, CategoryUpdateMutation(categorization="Mortgage"), category_id=9)
        self.assertEqual(response.nys_snw_category_id, 9)
        self.assertEqual(response.display_label, "EXPENSES > Housing > 2. > Mortgage")
        self.assertEqual(session.commits, 1)

    def test_write_category_returns_conflict_for_duplicate_hierarchy(self):
        #R050
        session = _IntegrityErrorSession(rows=[])
        with self.assertRaises(HTTPException) as ctx:
            _write_category(session, CategoryCreateMutation(level_1="II.", level_1_name="EXPENSES", categorization="Rent"))
        self.assertEqual(ctx.exception.status_code, 409)

    def test_category_mutation_rejects_control_characters(self):
        #R045
        with self.assertRaises(ValidationError):
            CategoryCreateMutation(level_1_name="EXPENSES", level_2_name="House\nhold")

    def test_write_category_rejects_empty_normalized_payload(self):
        #R045
        session = _FakeSession(rows=[])
        with self.assertRaises(ValidationError):
            _write_category(session, CategoryCreateMutation(level_1="   ", level_2_name=""))

    def test_category_mutation_rejects_null_field_values(self):
        #R045
        with self.assertRaises(ValidationError):
            CategoryUpdateMutation(level_1=None)

    def test_category_mutation_openapi_schema_requires_non_empty_object(self):
        #R045
        schemas = create_app().openapi()["components"]["schemas"]
        create_schema = schemas["CategoryCreateMutation"]
        update_schema = schemas["CategoryUpdateMutation"]
        self.assertEqual(create_schema.get("minProperties"), 1)
        self.assertEqual(update_schema.get("minProperties"), 1)
        level_1_schema = create_schema.get("properties", {}).get("level_1", {})
        self.assertEqual(level_1_schema.get("type"), "string")
        self.assertEqual(level_1_schema.get("minLength"), 1)
        self.assertEqual(level_1_schema.get("pattern"), r"^[\x20-\x7E]*[\x21-\x7E][\x20-\x7E]*$")

    def test_category_mutations_reject_empty_json_body(self):
        #R045
        with self.assertRaises(ValidationError):
            CategoryCreateMutation.model_validate({})
        with self.assertRaises(ValidationError):
            CategoryUpdateMutation.model_validate({})

    def test_category_operation_openapi_request_body_requires_non_empty_object(self):
        #R045
        schema = create_app().openapi()
        category_put_path = "/v1/categories/{nys_snw_category_id}"
        if category_put_path not in schema["paths"]:
            category_put_path = "/v1/categories/{nys_snw_category_id:int}"

        def _extract_category_schema(path: str, method: str):
            operation = schema["paths"][path][method]
            body_schema = operation["requestBody"]["content"]["application/json"]["schema"]
            ref = body_schema.get("$ref")
            if ref is None:
                refs = body_schema.get("allOf", [])
                self.assertTrue(refs)
                ref = refs[0]["$ref"]
            ref_name = ref.rsplit("/", 1)[1]
            return schema["components"]["schemas"][ref_name]

        create_schema = _extract_category_schema("/v1/categories", "post")
        update_schema = _extract_category_schema(category_put_path, "put")
        self.assertEqual(create_schema.get("minProperties"), 1)
        self.assertEqual(update_schema.get("minProperties"), 1)

    def test_write_category_rejects_seed_row_updates(self):
        session = _FakeSession(
            rows=[
                _Result(row=(1,)),
                _Result(
                    row={
                        "nys_snw_category_id": 7,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": "(a)",
                        "level_2_name": "Housing",
                        "level_3": "2.",
                        "level_4": None,
                        "categorization": "Rent",
                        "applicability": None,
                        "is_seed": True,
                    }
                ),
            ]
        )
        with self.assertRaises(HTTPException) as ctx:
            _write_category(session, CategoryUpdateMutation(categorization="Mortgage"), category_id=7)
        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("seed-protected", ctx.exception.detail)

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

    def test_classification_mutation_rejects_invalid_transaction_id(self):
        #R045
        with self.assertRaises(ValidationError):
            ClassificationMutation(transaction_id="txn with spaces", nys_snw_category_id=1)

    def test_single_classification_mutation_rejects_transaction_id_field(self):
        #R030
        with self.assertRaises(ValidationError):
            SingleClassificationMutation(transaction_id="txn_1", nys_snw_category_id=1)

    def test_single_classification_openapi_schema_omits_transaction_id(self):
        #R030
        schema = create_app().openapi()["components"]["schemas"]["SingleClassificationMutation"]
        self.assertNotIn("transaction_id", schema.get("properties", {}))

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
                        "is_seed": False,
                    }
                ),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint(
            request=self._authorized_request(),
            body=CategoryCreateMutation(level_1_name="EXPENSES", categorization="Pets"),
        )
        self.assertEqual(body.nys_snw_category_id, 55)
        self.assertEqual(body.display_label, "EXPENSES > Pets")

    @patch("teller.teller_classification_api.get_session")
    def test_create_category_endpoint_requires_write_token(self, get_session_mock):
        #R040
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories", "POST")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=SimpleNamespace(headers={}), body=CategoryCreateMutation(level_1_name="EXPENSES"))
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("teller.teller_classification_api.get_session")
    def test_create_category_endpoint_rejects_invalid_write_token(self, get_session_mock):
        #R040
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories", "POST")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=SimpleNamespace(headers={"x-teller-write-token": "wrong-token"}),
                body=CategoryCreateMutation(level_1_name="EXPENSES"),
            )
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("teller.teller_classification_api.get_session")
    def test_update_category_endpoint_404s_for_unknown_id(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "PUT")
        session = _FakeSession(rows=[_Result(row=None)])
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=self._authorized_request(),
                nys_snw_category_id=999,
                body=CategoryUpdateMutation(categorization="X"),
            )
        self.assertEqual(ctx.exception.status_code, 404)

    @patch("teller.teller_classification_api.get_session")
    def test_delete_category_rejects_assigned_categories(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "DELETE")
        session = _FakeSession(
            rows=[
                _Result(row=(1,)),
                _Result(
                    row={
                        "nys_snw_category_id": 4,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": "(a)",
                        "level_2_name": "Housing",
                        "level_3": "2.",
                        "level_4": None,
                        "categorization": "Rent",
                        "applicability": None,
                        "is_seed": False,
                    }
                ),
                _Result(scalar=2),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=self._authorized_request(), nys_snw_category_id=4)
        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("still reference", ctx.exception.detail)

    @patch("teller.teller_classification_api.get_session")
    def test_delete_category_succeeds_when_unassigned(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "DELETE")
        session = _FakeSession(
            rows=[
                _Result(row=(1,)),
                _Result(
                    row={
                        "nys_snw_category_id": 4,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": "(a)",
                        "level_2_name": "Housing",
                        "level_3": "2.",
                        "level_4": None,
                        "categorization": "Rent",
                        "applicability": None,
                        "is_seed": False,
                    }
                ),
                _Result(scalar=0),
                _Result(),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint(request=self._authorized_request(), nys_snw_category_id=4)
        self.assertEqual(body.nys_snw_category_id, 4)
        self.assertTrue(body.deleted)
        self.assertEqual(session.commits, 1)

    @patch("teller.teller_classification_api.get_session")
    def test_delete_category_rejects_seed_rows(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories/{nys_snw_category_id:int}", "DELETE")
        session = _FakeSession(
            rows=[
                _Result(row=(1,)),
                _Result(
                    row={
                        "nys_snw_category_id": 2,
                        "level_1": "II.",
                        "level_1_name": "EXPENSES",
                        "level_2": "(a)",
                        "level_2_name": "Housing",
                        "level_3": "2.",
                        "level_4": None,
                        "categorization": "Rent",
                        "applicability": None,
                        "is_seed": True,
                    }
                ),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=self._authorized_request(), nys_snw_category_id=2)
        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("seed-protected", ctx.exception.detail)

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
    def test_single_classification_uses_path_transaction_id(self, get_session_mock, write_one_mock):
        #R030
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions/{transaction_id}/classification", "PUT")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        endpoint(
            request=self._authorized_request(),
            transaction_id="txn_path",
            body=SingleClassificationMutation(nys_snw_category_id=12),
        )
        write_one_mock.assert_called_once_with(unittest.mock.ANY, "txn_path", 12)

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_requires_non_empty_updates(self, get_session_mock, write_one_mock):
        #R035
        with self.assertRaises(ValidationError):
            ClassificationBatchRequest(updates=[])
        write_one_mock.assert_not_called()

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_rejects_excessive_batch_size(self, get_session_mock, write_one_mock):
        #R045
        with self.assertRaises(ValidationError):
            ClassificationBatchRequest(
                updates=[ClassificationMutation(transaction_id=f"txn_{idx}", nys_snw_category_id=1) for idx in range(251)]
            )
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
            request=self._authorized_request(),
            body=SimpleNamespace(
                updates=[
                    SimpleNamespace(transaction_id="txn_1", nys_snw_category_id=1),
                    SimpleNamespace(transaction_id="txn_2", nys_snw_category_id=None),
                ]
            )
        )
        self.assertEqual(len(response), 2)
        self.assertEqual(write_one_mock.call_count, 2)

    @patch("teller.teller_classification_api._insert_match_audit")
    @patch("teller.teller_classification_api._read_match_row")
    def test_transition_match_state_clears_email_with_expression_update(self, read_match_row_mock, insert_audit_mock):
        read_match_row_mock.return_value = {"state": "ai_match_confident"}
        session = _FakeSession(
            rows=[
                _Result(
                    row={
                        "transaction_id": "txn_1",
                        "state": "ai_no_match_found",
                        "selected_by": "human",
                        "updated_at": datetime.now(timezone.utc),
                    }
                )
            ]
        )

        response = _transition_match_state(
            session=session,
            match_id=7,
            to_state="ai_no_match_found",
            actor="human",
            note="no email found",
            clear_email_message_id=True,
        )

        self.assertEqual(response.transaction_id, "txn_1")
        self.assertEqual(response.state, "ai_no_match_found")
        self.assertEqual(response.selected_by, "human")
        self.assertEqual(session.commits, 1)
        update_sql, update_params = session.calls[0]
        self.assertIn("UPDATE teller.transaction_email_match", update_sql)
        self.assertIn("email_message_id", update_sql)
        self.assertNotIn("email_message_id", update_params)
        insert_audit_mock.assert_called_once()

    @patch("teller.teller_classification_api._insert_match_audit")
    @patch("teller.teller_classification_api._read_match_row")
    def test_transition_match_state_sets_email_with_expression_update(self, read_match_row_mock, insert_audit_mock):
        read_match_row_mock.return_value = {"state": "ai_candidate_uncertain"}
        session = _FakeSession(
            rows=[
                _Result(
                    row={
                        "transaction_id": "txn_2",
                        "state": "human_overrode_ai_match",
                        "selected_by": "human",
                        "updated_at": datetime.now(timezone.utc),
                    }
                )
            ]
        )

        response = _transition_match_state(
            session=session,
            match_id=8,
            to_state="human_overrode_ai_match",
            actor="human",
            note="manual override",
            email_message_id="msg_123",
        )

        self.assertEqual(response.transaction_id, "txn_2")
        self.assertEqual(response.state, "human_overrode_ai_match")
        self.assertEqual(session.commits, 1)
        update_sql, update_params = session.calls[0]
        self.assertIn("UPDATE teller.transaction_email_match", update_sql)
        self.assertIn("email_message_id", update_sql)
        self.assertEqual(update_params["email_message_id"], "msg_123")
        insert_audit_mock.assert_called_once()

    @patch("teller.teller_classification_api._read_match_row")
    def test_transition_match_state_returns_409_on_constraint_violation(self, read_match_row_mock):
        read_match_row_mock.return_value = {"state": "ai_match_confident"}
        session = _IntegrityErrorSession(rows=[])

        with self.assertRaises(HTTPException) as ctx:
            _transition_match_state(
                session=session,
                match_id=11,
                to_state="human_confirmed_ai_match",
                actor="human",
                note="confirm after no-email",
            )

        self.assertEqual(ctx.exception.status_code, 409)
        self.assertIn("conflicts with current state", str(ctx.exception.detail))

    @patch("teller.teller_classification_api.get_session")
    def test_matchy_review_applies_filter_predicates_with_expression_queries(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/review", "GET")
        session = _FakeSession(
            rows=[
                _Result(scalar=1),
                _Result(
                    rows=[
                        {
                            "match_id": 19,
                            "transaction_id": "txn_9",
                            "email_message_id": "msg_9",
                            "state": "ai_match_confident",
                            "ai_confidence": 0.88,
                            "selected_by": "ai",
                            "selected_at": datetime.now(timezone.utc),
                            "moved_to_matchy_at": None,
                            "description": "Lunch",
                            "amount": "12.34",
                            "date": "2026-01-02",
                        }
                    ]
                ),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)

        response = endpoint(
            state="ai_match_confident",
            only_unmoved=True,
            limit=10,
            offset=3,
        )

        self.assertEqual(response.total, 1)
        self.assertEqual(len(response.items), 1)
        count_sql, count_params = session.calls[0]
        rows_sql, rows_params = session.calls[1]
        self.assertIn("FROM teller.transaction_email_match", count_sql)
        self.assertIn("moved_to_matchy_at IS NULL", count_sql)
        self.assertNotIn("{where_sql}", count_sql)
        self.assertIn("JOIN teller.transaction", rows_sql)
        self.assertIn("ORDER BY teller.transaction_email_match.selected_at DESC", rows_sql)
        self.assertEqual(count_params["state"], "ai_match_confident")
        self.assertEqual(rows_params["limit"], 10)
        self.assertEqual(rows_params["offset"], 3)

    def test_matchy_mutation_openapi_documents_not_found_responses(self):
        #R055
        schema = create_app().openapi()
        endpoints = [
            ("/v1/matchy/matches/{match_id}/confirm", "put"),
            ("/v1/matchy/matches/{match_id}/override", "put"),
            ("/v1/matchy/matches/{match_id}/no-email", "put"),
        ]
        for path, method in endpoints:
            responses = schema["paths"][path][method]["responses"]
            self.assertIn("404", responses, f"Missing 404 for {method.upper()} {path}")
            self.assertIn("409", responses, f"Missing 409 for {method.upper()} {path}")

    @patch("teller.teller_classification_api.get_session")
    def test_matchy_mutation_endpoints_return_404_for_unknown_match_ids(self, get_session_mock):
        #R055
        app = create_app()
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        unknown_err = HTTPException(status_code=404, detail="Unknown match_id: 999")
        with patch("teller.teller_classification_api._read_match_row", side_effect=unknown_err):
            confirm_endpoint = self._route_endpoint(app, "/v1/matchy/matches/{match_id:int}/confirm", "PUT")
            no_email_endpoint = self._route_endpoint(app, "/v1/matchy/matches/{match_id:int}/no-email", "PUT")
            override_endpoint = self._route_endpoint(app, "/v1/matchy/matches/{match_id:int}/override", "PUT")

            with self.assertRaises(HTTPException) as confirm_ctx:
                confirm_endpoint(request=self._authorized_request(), match_id=999)
            self.assertEqual(confirm_ctx.exception.status_code, 404)

            with self.assertRaises(HTTPException) as no_email_ctx:
                no_email_endpoint(request=self._authorized_request(), match_id=999)
            self.assertEqual(no_email_ctx.exception.status_code, 404)

            with self.assertRaises(HTTPException) as override_ctx:
                override_endpoint(
                    request=self._authorized_request(),
                    match_id=999,
                    body=SimpleNamespace(email_message_id="m_1", note="manual"),
                )
            self.assertEqual(override_ctx.exception.status_code, 404)

if __name__ == "__main__":
    unittest.main()
