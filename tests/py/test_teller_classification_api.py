import unittest
from datetime import datetime, timezone
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from types import SimpleNamespace
from unittest.mock import patch

try:
    from fastapi.testclient import TestClient
except RuntimeError:
    TestClient = None

from teller.teller_classification_api import (
    _estimate_transaction_total,
    _category_params,
    _create_transaction_match,
    _deactivate_match,
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
from teller.teller_mailcart_client import MailcartError


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

    def __exit__(self, *args):
        return False


class ClassificationApiTests(unittest.TestCase):
    def test_estimate_transaction_total(self):
        self.assertEqual(_estimate_transaction_total(offset=0, limit=150, row_count=2), 2)
        self.assertEqual(_estimate_transaction_total(offset=0, limit=150, row_count=150), 151)
        self.assertEqual(_estimate_transaction_total(offset=150, limit=150, row_count=50), 200)

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
        #R001-T01
        app = create_app()
        route_paths = {route.path for route in app.routes}
        self.assertIn("/health", route_paths)
        self.assertIn("/v1/categories", route_paths)
        self.assertIn("/v1/categories/{nys_snw_category_id:int}", route_paths)
        self.assertIn("/v1/categories/counts", route_paths)
        self.assertIn("/v1/transactions", route_paths)
        self.assertIn("/v1/transactions/{transaction_id}/classification", route_paths)
        self.assertIn("/v1/transactions/classifications", route_paths)

    @unittest.skipIf(TestClient is None, "fastapi testclient optional dependency (httpx) is not installed")
    def test_health_endpoint_returns_ok_over_http(self):
        client = TestClient(create_app())
        response = client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"ok": True})

    @unittest.skipIf(TestClient is None, "fastapi testclient optional dependency (httpx) is not installed")
    def test_http_categories_endpoint_requires_write_token(self):
        client = TestClient(create_app())
        response = client.get("/v1/categories")
        self.assertEqual(response.status_code, 401)
        self.assertIn("Missing write token header", response.json()["detail"])

    @unittest.skipIf(TestClient is None, "fastapi testclient optional dependency (httpx) is not installed")
    def test_http_category_counts_write_methods_return_405(self):
        client = TestClient(create_app())
        response = client.post("/v1/categories/counts")
        self.assertEqual(response.status_code, 405)
        self.assertEqual(response.headers.get("allow"), "GET")

    def test_display_label_joins_hierarchy(self):
        #R005-T01
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
        #R050-T01
        session = _IntegrityErrorSession(rows=[])
        with self.assertRaises(HTTPException) as ctx:
            _write_category(session, CategoryCreateMutation(level_1="II.", level_1_name="EXPENSES", categorization="Rent"))
        self.assertEqual(ctx.exception.status_code, 409)

    def test_category_mutation_rejects_control_characters(self):
        #R045-T01
        with self.assertRaises(ValidationError):
            CategoryCreateMutation(level_1_name="EXPENSES", level_2_name="House\nhold")

    def test_write_category_rejects_empty_normalized_payload(self):
        #R045-T02
        session = _FakeSession(rows=[])
        with self.assertRaises(ValidationError):
            _write_category(session, CategoryCreateMutation(level_1="   ", level_2_name=""))

    def test_category_mutation_rejects_null_field_values(self):
        #R045-T03
        with self.assertRaises(ValidationError):
            CategoryUpdateMutation(level_1=None)

    def test_category_mutation_openapi_schema_requires_non_empty_object(self):
        #R045-T03
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
        #R045-T03
        with self.assertRaises(ValidationError):
            CategoryCreateMutation.model_validate({})
        with self.assertRaises(ValidationError):
            CategoryUpdateMutation.model_validate({})

    def test_category_operation_openapi_request_body_requires_non_empty_object(self):
        #R045-T03
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
        #R025-T01
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
        #R025-T02
        session = _FakeSession(rows=[_Result(row=(1,))])
        response = _write_one(session, "txn_3", None)
        self.assertIsNone(response.nys_snw_category_id)
        self.assertEqual(session.commits, 1)

    def test_write_one_raises_on_unknown_transaction(self):
        #R025-T03
        session = _FakeSession(rows=[_Result(row=None)])
        with self.assertRaises(HTTPException) as ctx:
            _write_one(session, "txn_missing", 12)
        self.assertEqual(ctx.exception.status_code, 404)

    def test_write_one_raises_on_unknown_category(self):
        #R025-T03
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(row=None)])
        with self.assertRaises(HTTPException) as ctx:
            _write_one(session, "txn_1", 999)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("Unknown nys_snw_category_id", ctx.exception.detail)

    def test_classification_mutation_rejects_invalid_transaction_id(self):
        #R045-T04
        with self.assertRaises(ValidationError):
            ClassificationMutation(transaction_id="txn with spaces", nys_snw_category_id=1)

    def test_single_classification_mutation_rejects_transaction_id_field(self):
        #R030-T01
        with self.assertRaises(ValidationError):
            SingleClassificationMutation(transaction_id="txn_1", nys_snw_category_id=1)

    def test_single_classification_openapi_schema_omits_transaction_id(self):
        #R030-T01
        schema = create_app().openapi()["components"]["schemas"]["SingleClassificationMutation"]
        self.assertNotIn("transaction_id", schema.get("properties", {}))

    @patch("teller.teller_classification_api.get_session")
    def test_categories_endpoint_returns_display_labels(self, get_session_mock):
        #R010-T01
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
        body = endpoint(request=self._authorized_request())
        self.assertEqual(body[0].display_label, "EXPENSES > Groceries")

    @patch("teller.teller_classification_api.get_session")
    def test_categories_endpoint_requires_write_token(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories", "GET")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=SimpleNamespace(headers={}))
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("teller.teller_classification_api.get_session")
    def test_category_counts_includes_zero_assignment_categories(self, get_session_mock):
        #R015-T01
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
        body = endpoint(request=self._authorized_request())
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
        #R040-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/categories", "POST")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=SimpleNamespace(headers={}), body=CategoryCreateMutation(level_1_name="EXPENSES"))
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("teller.teller_classification_api.get_session")
    def test_create_category_endpoint_rejects_invalid_write_token(self, get_session_mock):
        #R040-T02
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
    def test_batch_classification_endpoint_requires_write_token(self, get_session_mock):
        #R040-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions/classifications", "POST")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=SimpleNamespace(headers={}),
                body=ClassificationBatchRequest(updates=[ClassificationMutation(transaction_id="txn_1", nys_snw_category_id=2)]),
            )
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_endpoint_rejects_invalid_write_token(self, get_session_mock):
        #R040-T02
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions/classifications", "POST")
        get_session_mock.return_value = _SessionContext(_FakeSession(rows=[]))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=SimpleNamespace(headers={"x-teller-write-token": "wrong-token"}),
                body=ClassificationBatchRequest(updates=[ClassificationMutation(transaction_id="txn_1", nys_snw_category_id=2)]),
            )
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_list_endpoint_requires_write_token(self, get_session_mock):
        #R040-T03
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(rows=[_Result(rows=[]), _Result(scalar=0)])
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=SimpleNamespace(headers={}, query_params={}),
                search="",
                status="",
                only_unclassified=False,
                match_state="",
                only_unmoved_match=False,
                include_total=True,
                count_only=False,
                limit=100,
                offset=0,
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
        #R020-T01
        #R020-T02
        #R020-T03
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(
            rows=[
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
                _Result(scalar=1),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={
                "search": "cof",
                "status": "posted",
                "only_unclassified": "true",
                "limit": "10",
                "offset": "2",
            }
        )
        body = endpoint(
            request=request,
            search="cof",
            status="posted",
            only_unclassified=True,
            match_state="",
            only_unmoved_match=False,
            include_total=True,
            count_only=False,
            limit=10,
            offset=2,
        )
        self.assertEqual(body.total, 1)
        self.assertEqual(len(body.items), 1)
        list_sql, list_params = session.calls[0]
        count_sql, count_params = session.calls[1]
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

    def test_transactions_endpoint_rejects_unknown_query_params(self):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "extra_flag": "1"},
        )
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=request,
                search="",
                status="",
                only_unclassified=False,
                match_state="",
                only_unmoved_match=False,
                limit=10,
                offset=0,
            )
        self.assertEqual(ctx.exception.status_code, 400)
        self.assertIn("Unknown query parameters", str(ctx.exception.detail))

    def test_transactions_endpoint_rejects_invalid_only_unclassified_value(self):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"only_unclassified": "sometimes"},
        )
        with self.assertRaises(HTTPException) as ctx:
            endpoint(
                request=request,
                search="",
                status="",
                only_unclassified=False,
                match_state="",
                only_unmoved_match=False,
                limit=10,
                offset=0,
            )
        self.assertEqual(ctx.exception.status_code, 422)
        self.assertIsInstance(ctx.exception.detail, list)

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_single_classification_uses_path_transaction_id(self, get_session_mock, write_one_mock):
        #R030-T01
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
        #R035-T01
        with self.assertRaises(ValidationError):
            ClassificationBatchRequest(updates=[])
        write_one_mock.assert_not_called()

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_rejects_excessive_batch_size(self, get_session_mock, write_one_mock):
        #R045-T04
        with self.assertRaises(ValidationError):
            ClassificationBatchRequest(
                updates=[ClassificationMutation(transaction_id=f"txn_{idx}", nys_snw_category_id=1) for idx in range(251)]
            )
        write_one_mock.assert_not_called()

    @patch("teller.teller_classification_api._write_one")
    @patch("teller.teller_classification_api.get_session")
    def test_batch_classification_returns_one_row_per_input(self, get_session_mock, write_one_mock):
        #R035-T02
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

    @patch("teller.teller_classification_api._insert_match_audit")
    @patch("teller.teller_classification_api._read_active_match_row")
    def test_deactivate_match_sets_active_false(self, read_active_match_row_mock, insert_audit_mock):
        #R071-T01
        #R071-T02
        read_active_match_row_mock.return_value = {
            "match_id": 12,
            "transaction_id": "txn_1",
            "state": "human_confirmed_ai_match",
            "selected_by": "human",
        }
        session = _FakeSession(
            rows=[
                _Result(
                    row={
                        "transaction_id": "txn_1",
                        "state": "human_confirmed_ai_match",
                        "selected_by": "human",
                        "updated_at": datetime.now(timezone.utc),
                    }
                )
            ]
        )

        response = _deactivate_match(session=session, match_id=12, note="Cleared from Teller review UI")

        self.assertEqual(response.transaction_id, "txn_1")
        self.assertEqual(response.state, "human_confirmed_ai_match")
        self.assertEqual(session.commits, 1)
        update_sql, _ = session.calls[0]
        self.assertIn("UPDATE teller.transaction_email_match", update_sql)
        self.assertIn("active", update_sql)
        insert_audit_mock.assert_called_once()

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
            request=self._authorized_request(),
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
        #R055-T01
        schema = create_app().openapi()
        endpoints = [
            ("/v1/matchy/matches/{match_id}/confirm", "put"),
            ("/v1/matchy/matches/{match_id}/override", "put"),
            ("/v1/matchy/matches/{match_id}/no-email", "put"),
            ("/v1/matchy/matches/{match_id}/clear", "put"),
            ("/v1/matchy/transactions/{transaction_id}/clear", "put"),
        ]
        for path, method in endpoints:
            responses = schema["paths"][path][method]["responses"]
            self.assertIn("404", responses, f"Missing 404 for {method.upper()} {path}")
            self.assertIn("409", responses, f"Missing 409 for {method.upper()} {path}")

    @patch("teller.teller_classification_api.get_session")
    def test_matchy_mutation_endpoints_return_404_for_unknown_match_ids(self, get_session_mock):
        #R055-T02
        #R071-T03
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

        with patch("teller.teller_classification_api._read_active_match_row", side_effect=unknown_err):
            clear_endpoint = self._route_endpoint(app, "/v1/matchy/matches/{match_id:int}/clear", "PUT")
            with self.assertRaises(HTTPException) as clear_ctx:
                clear_endpoint(request=self._authorized_request(), match_id=999)
            self.assertEqual(clear_ctx.exception.status_code, 404)

class _FakeMailcartClient:
    def __init__(self, *, messages=None, message_errors=None, search_payload=None, search_error=None):
        self._messages = dict(messages or {})
        self._message_errors = dict(message_errors or {})
        self._search_payload = search_payload
        self._search_error = search_error
        self.get_message_calls = []
        self.search_calls = []

    def get_message(self, email_message_id):
        self.get_message_calls.append(email_message_id)
        if email_message_id in self._message_errors:
            raise self._message_errors[email_message_id]
        if email_message_id not in self._messages:
            raise MailcartError(status_code=404, message="mailcart: message not found")
        return self._messages[email_message_id]

    def search(self, query, limit):
        self.search_calls.append({"query": query, "limit": limit})
        if self._search_error is not None:
            raise self._search_error
        return self._search_payload


class MatchCandidateProxyTests(unittest.TestCase):
    def setUp(self):
        self._mailcart_patches = []
        self._token_patch = patch(
            "teller.teller_classification_api._configured_write_token",
            return_value="test-write-token",
        )
        self._token_patch.start()

    def tearDown(self):
        for patcher in self._mailcart_patches:
            patcher.stop()
        self._token_patch.stop()

    def _route_endpoint(self, app, path, method):
        for route in app.routes:
            if getattr(route, "path", None) == path and method in getattr(route, "methods", set()):
                return route.endpoint
        raise AssertionError(f"route not found: {method} {path}")

    def _install_mailcart_client(self, client):
        patcher = patch("teller.teller_classification_api.get_mailcart_client", return_value=client)
        self._mailcart_patches.append(patcher)
        patcher.start()

    def _authorized_request(self):
        return SimpleNamespace(headers={"x-teller-write-token": "test-write-token"})

    @patch("teller.teller_classification_api.get_session")
    def test_list_candidates_returns_latest_run_only_sorted_by_score(self, get_session_mock):
        #R060-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/transactions/{transaction_id}/candidates", "GET")
        candidate_rows = [
            {
                "candidate_id": 1, "email_message_id": "msg_high",
                "score": 0.92,
                "reason_json": {"reason": "amount-and-date match"},
                "email_received_at": datetime(2026, 5, 17, 12, 0, tzinfo=timezone.utc),
                "is_selected_by_ai": True,
                "is_unmatched_email_priority": False,
            },
            {
                "candidate_id": 2, "email_message_id": "msg_low",
                "score": 0.41,
                "reason_json": {},
                "email_received_at": datetime(2026, 5, 16, 8, 30, tzinfo=timezone.utc),
                "is_selected_by_ai": False,
                "is_unmatched_email_priority": True,
            },
        ]
        session = _FakeSession(rows=[_Result(row=(42,)), _Result(rows=candidate_rows)])
        get_session_mock.return_value = _SessionContext(session)
        self._install_mailcart_client(
            _FakeMailcartClient(messages={
                "msg_high": {"subject": "Order receipt", "from": "shop@example.com", "snippet": "Thanks!"},
                "msg_low":  {"subject": "Newsletter", "from": "news@example.com", "snippet": "Hi"},
            })
        )

        body = endpoint(request=self._authorized_request(), transaction_id="txn_42")

        self.assertEqual([row.email_message_id for row in body], ["msg_high", "msg_low"])
        self.assertEqual(body[0].subject, "Order receipt")
        self.assertTrue(body[0].is_selected_by_ai)
        self.assertEqual(body[1].subject, "Newsletter")
        self.assertTrue(body[1].is_unmatched_email_priority)
        run_sql, run_params = session.calls[0]
        cand_sql, cand_params = session.calls[1]
        self.assertIn("FROM teller.transaction_email_match_run", run_sql)
        self.assertEqual(run_params["transaction_id"], "txn_42")
        self.assertIn("transaction_email_candidate", cand_sql)
        self.assertIn("ORDER BY score DESC", cand_sql)
        self.assertEqual(cand_params["match_run_id"], 42)

    @patch("teller.teller_classification_api.get_session")
    def test_list_candidates_merges_mailcart_metadata_onto_db_rows(self, get_session_mock):
        #R060-T02
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/transactions/{transaction_id}/candidates", "GET")
        session = _FakeSession(rows=[
            _Result(row=(7,)),
            _Result(rows=[{
                "candidate_id": 3, "email_message_id": "msg_1",
                "score": 0.5,
                "reason_json": {"why": "fuzzy"},
                "email_received_at": None,
                "is_selected_by_ai": False,
                "is_unmatched_email_priority": False,
            }]),
        ])
        get_session_mock.return_value = _SessionContext(session)
        self._install_mailcart_client(_FakeMailcartClient(messages={
            "msg_1": {"subject": "Hello", "from": "alice@example.com", "snippet": "preview"},
        }))

        body = endpoint(request=self._authorized_request(), transaction_id="txn_with_one_run")

        self.assertEqual(len(body), 1)
        self.assertEqual(body[0].subject, "Hello")
        self.assertEqual(body[0].sender, "alice@example.com")
        self.assertEqual(body[0].snippet, "preview")
        self.assertEqual(body[0].reason_json, {"why": "fuzzy"})
        self.assertIsNone(body[0].mailcart_error)

    @patch("teller.teller_classification_api.get_session")
    def test_list_candidates_partial_mailcart_failure_does_not_500(self, get_session_mock):
        #R060-T03
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/transactions/{transaction_id}/candidates", "GET")
        session = _FakeSession(rows=[
            _Result(row=(8,)),
            _Result(rows=[
                {"candidate_id": 4, "email_message_id": "msg_ok",   "score": 0.7, "reason_json": {}, "email_received_at": None,
                 "is_selected_by_ai": False, "is_unmatched_email_priority": False},
                {"candidate_id": 5, "email_message_id": "msg_bad",  "score": 0.6, "reason_json": {}, "email_received_at": None,
                 "is_selected_by_ai": False, "is_unmatched_email_priority": False},
            ]),
        ])
        get_session_mock.return_value = _SessionContext(session)
        self._install_mailcart_client(_FakeMailcartClient(
            messages={"msg_ok": {"subject": "Good", "from": "ok@example.com", "snippet": "ok"}},
            message_errors={"msg_bad": MailcartError(status_code=502, message="mailcart: upstream returned 500")},
        ))

        body = endpoint(request=self._authorized_request(), transaction_id="txn_42")

        self.assertEqual(body[0].subject, "Good")
        self.assertIsNone(body[0].mailcart_error)
        self.assertIsNone(body[1].subject)
        self.assertEqual(body[1].mailcart_error, "mailcart: upstream returned 500")

    @patch("teller.teller_classification_api.get_session")
    def test_list_candidates_returns_404_when_no_runs_exist(self, get_session_mock):
        #R060-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/transactions/{transaction_id}/candidates", "GET")
        session = _FakeSession(rows=[_Result(row=None)])
        get_session_mock.return_value = _SessionContext(session)
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=self._authorized_request(), transaction_id="txn_missing")
        self.assertEqual(ctx.exception.status_code, 404)

    @patch("teller.teller_classification_api.get_session")
    def test_list_candidates_returns_empty_when_run_has_no_candidates(self, get_session_mock):
        #R060-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/transactions/{transaction_id}/candidates", "GET")
        session = _FakeSession(rows=[_Result(row=(1,)), _Result(rows=[])])
        get_session_mock.return_value = _SessionContext(session)
        body = endpoint(request=self._authorized_request(), transaction_id="txn_no_candidates")
        self.assertEqual(body, [])

    def test_get_message_proxies_body_and_metadata(self):
        #R061-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/{email_message_id}", "GET")
        self._install_mailcart_client(_FakeMailcartClient(messages={
            "msg_42": {
                "email_message_id": "msg_42",
                "subject": "Receipt",
                "from": "store@example.com",
                "to": "me@example.com",
                "received_at": "2026-05-17T12:00:00+00:00",
                "html_body": "<p>hi</p>",
                "text_body": "hi",
                "snippet": "hi",
            }
        }))
        body = endpoint(request=self._authorized_request(), email_message_id="msg_42")
        self.assertEqual(body.email_message_id, "msg_42")
        self.assertEqual(body.subject, "Receipt")
        self.assertEqual(body.sender, "store@example.com")
        self.assertEqual(body.recipients, "me@example.com")
        self.assertEqual(body.html_body, "<p>hi</p>")
        self.assertEqual(body.text_body, "hi")

    def test_get_message_surfaces_404_from_mailcart(self):
        #R061-T02
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/{email_message_id}", "GET")
        self._install_mailcart_client(_FakeMailcartClient())
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=self._authorized_request(), email_message_id="msg_missing")
        self.assertEqual(ctx.exception.status_code, 404)

    def test_get_message_requires_write_token(self):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/{email_message_id}", "GET")
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=SimpleNamespace(headers={}), email_message_id="msg_missing")
        self.assertEqual(ctx.exception.status_code, 401)

    def test_get_message_rejects_invalid_identifier(self):
        #R061-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/{email_message_id}", "GET")
        self._install_mailcart_client(_FakeMailcartClient())
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=self._authorized_request(), email_message_id="bad id with space")
        self.assertEqual(ctx.exception.status_code, 400)

    def test_search_messages_validates_query_and_proxies_items(self):
        #R062-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/search", "GET")
        client = _FakeMailcartClient(search_payload={"items": [
            {"email_message_id": "msg_a", "subject": "A", "from": "a@example.com", "received_at": "2026-05-17T12:00:00+00:00", "snippet": "..."},
            {"email_message_id": "msg_b", "subject": "B", "from": "b@example.com", "received_at": "2026-05-17T13:00:00+00:00", "snippet": "..."},
        ]})
        self._install_mailcart_client(client)
        body = endpoint(request=self._authorized_request(), query="amazon receipt", limit=5)
        self.assertEqual(body.query, "amazon receipt")
        self.assertEqual([hit.email_message_id for hit in body.items], ["msg_a", "msg_b"])
        self.assertEqual(client.search_calls, [{"query": "amazon receipt", "limit": 5}])

    def test_search_messages_502s_when_upstream_returns_no_items_array(self):
        #R062-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/search", "GET")
        self._install_mailcart_client(_FakeMailcartClient(search_payload={"not_items": []}))
        with self.assertRaises(HTTPException) as ctx:
            endpoint(request=self._authorized_request(), query="q", limit=5)
        self.assertEqual(ctx.exception.status_code, 502)

    def test_search_messages_accepts_real_mailcart_messages_envelope(self):
        #R062-T02
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/search", "GET")
        client = _FakeMailcartClient(search_payload={"messages": [
            {"message_id": "msg_a", "subject": "Receipt", "sender": "store@example.com",
             "preview": "preview text", "received_at": "2026-05-17T12:00:00+00:00", "body_text": "preview text"},
            {"message_id": "msg_b", "subject": "Bill", "sender": "biller@example.com",
             "preview": "second", "received_at": "2026-05-17T13:00:00+00:00", "body_text": "second"},
        ]})
        self._install_mailcart_client(client)
        body = endpoint(request=self._authorized_request(), query="amazon", limit=5)
        self.assertEqual([hit.email_message_id for hit in body.items], ["msg_a", "msg_b"])
        self.assertEqual(body.items[0].sender, "store@example.com")
        self.assertEqual(body.items[0].snippet, "preview text")

    def test_search_route_is_registered_before_message_id_route(self):
        #R062-T03
        app = create_app()
        route_paths = [route.path for route in app.routes if hasattr(route, "path")]
        search_idx = route_paths.index("/v1/matchy/messages/search")
        message_idx = route_paths.index("/v1/matchy/messages/{email_message_id}")
        self.assertLess(search_idx, message_idx)

    def test_search_path_matches_search_route_not_message_id_capture(self):
        #R062-T03
        from starlette.routing import Match

        app = create_app()
        scope = {
            "type": "http",
            "http_version": "1.1",
            "method": "GET",
            "path": "/v1/matchy/messages/search",
            "raw_path": b"/v1/matchy/messages/search",
            "root_path": "",
            "scheme": "http",
            "query_string": b"query=phil&limit=5",
            "headers": [],
            "client": ("test", 50000),
            "server": ("testserver", 80),
        }
        matched_path = None
        for route in app.routes:
            if not hasattr(route, "matches"):
                continue
            match, _child_scope = route.matches(scope)
            if match == Match.FULL:
                matched_path = route.path
                break
        self.assertEqual(matched_path, "/v1/matchy/messages/search")

    def test_get_message_accepts_real_mailcart_payload_shape(self):
        #R061-T03
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/messages/{email_message_id}", "GET")
        self._install_mailcart_client(_FakeMailcartClient(messages={
            "AAMkADk": {
                "message_id": "AAMkADk",
                "subject": "Receipt",
                "sender": "store@example.com",
                "recipients": "me@example.com,cc@example.com",
                "preview": "Thanks for your order",
                "received_at": "2026-05-17T12:00:00+00:00",
                "html_body": "<p>Thanks!</p>",
                "text_body": "",
                "body_text": "<p>Thanks!</p>",
            }
        }))
        body = endpoint(request=self._authorized_request(), email_message_id="AAMkADk")
        self.assertEqual(body.email_message_id, "AAMkADk")
        self.assertEqual(body.subject, "Receipt")
        self.assertEqual(body.sender, "store@example.com")
        self.assertEqual(body.recipients, "me@example.com,cc@example.com")
        self.assertEqual(body.html_body, "<p>Thanks!</p>")
        self.assertEqual(body.snippet, "Thanks for your order")

    @patch("teller.teller_classification_api.get_session")
    def test_list_candidates_merges_real_mailcart_shape(self, get_session_mock):
        #R060-T04
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/matchy/transactions/{transaction_id}/candidates", "GET")
        session = _FakeSession(rows=[
            _Result(row=(11,)),
            _Result(rows=[{
                "candidate_id": 99,
                "email_message_id": "AAMkADk",
                "score": 0.81,
                "reason_json": {"why": "amount"},
                "email_received_at": None,
                "is_selected_by_ai": True,
                "is_unmatched_email_priority": False,
            }]),
        ])
        get_session_mock.return_value = _SessionContext(session)
        self._install_mailcart_client(_FakeMailcartClient(messages={
            "AAMkADk": {
                "message_id": "AAMkADk",
                "subject": "Order receipt",
                "sender": "shop@example.com",
                "preview": "Thanks for your order",
                "body_text": "Thanks for your order, here are the details...",
            }
        }))
        body = endpoint(request=self._authorized_request(), transaction_id="txn_real")
        self.assertEqual(body[0].subject, "Order receipt")
        self.assertEqual(body[0].sender, "shop@example.com")
        self.assertEqual(body[0].snippet, "Thanks for your order")
        self.assertTrue(body[0].is_selected_by_ai)

    def test_matchy_extension_endpoints_register_with_app(self):
        #R060-T01
        app = create_app()
        route_paths = {route.path for route in app.routes}
        self.assertIn("/v1/matchy/transactions/{transaction_id}/candidates", route_paths)
        self.assertIn("/v1/matchy/transactions/{transaction_id}/confirm-candidate", route_paths)
        self.assertIn("/v1/matchy/transactions/{transaction_id}/override-candidate", route_paths)
        self.assertIn("/v1/matchy/transactions/{transaction_id}/no-email", route_paths)
        self.assertIn("/v1/matchy/transactions/{transaction_id}/clear", route_paths)
        self.assertIn("/v1/matchy/matches/{match_id:int}/clear", route_paths)
        self.assertIn("/v1/matchy/messages/{email_message_id}", route_paths)
        self.assertIn("/v1/matchy/messages/search", route_paths)

    @patch("teller.teller_classification_api._insert_match_audit")
    @patch("teller.teller_classification_api._ensure_candidate_for_transaction")
    @patch("teller.teller_classification_api._ensure_no_active_match")
    @patch("teller.teller_classification_api._ensure_posted_transaction")
    def test_create_transaction_match_inserts_confirmed_candidate(
        self,
        ensure_posted_mock,
        ensure_no_active_mock,
        ensure_candidate_mock,
        insert_audit_mock,
    ):
        session = _FakeSession(
            rows=[
                _Result(row={"match_id": 99, "updated_at": datetime.now(timezone.utc)}),
            ]
        )
        response = _create_transaction_match(
            session=session,
            transaction_id="txn_1",
            email_message_id="msg_abc",
            to_state="human_confirmed_ai_match",
            actor="human",
            note="Confirmed candidate from Teller review UI",
        )
        self.assertEqual(response.match_id, 99)
        self.assertEqual(response.transaction_id, "txn_1")
        self.assertEqual(response.state, "human_confirmed_ai_match")
        ensure_posted_mock.assert_called_once()
        ensure_no_active_mock.assert_called_once()
        ensure_candidate_mock.assert_called_once()
        insert_audit_mock.assert_called_once()
        self.assertEqual(session.commits, 1)

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_endpoint_includes_active_match_info(self, get_session_mock):
        #R070-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(
            rows=[
                _Result(
                    rows=[
                        {
                            "transaction_id": "txn_x", "account_id": "acc_x",
                            "institution_id": None, "account_last_four": None,
                            "date": "2026-05-06", "amount": "200.00", "description": "Cursor",
                            "status": "posted", "transaction_type_code": "card_payment",
                            "teller_category": None,
                            "nys_snw_category_id": None, "level_1": None, "level_1_name": None,
                            "level_2": None, "level_2_name": None, "level_3": None, "level_4": None,
                            "categorization": None,
                            "match_id": 351, "match_state": "ai_match_confident",
                            "match_selected_by": "ai",
                            "match_email_message_id": "msg_abc", "moved_to_matchy_at": None,
                            "match_ai_confidence": 0.95, "match_count": 3,
                        }
                    ]
                ),
                _Result(scalar=1),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "only_unclassified": "false",
                          "match_state": "ai_match_confident", "limit": "10", "offset": "0"}
        )
        body = endpoint(
            request=request,
            search="",
            status="",
            only_unclassified=False,
            match_state="ai_match_confident",
            only_unmoved_match=False,
            include_total=True,
            count_only=False,
            limit=10,
            offset=0,
        )
        self.assertEqual(body.total, 1)
        self.assertEqual(body.items[0].transaction_id, "txn_x")
        self.assertIsNotNone(body.items[0].match)
        self.assertEqual(body.items[0].match.match_id, 351)
        self.assertEqual(body.items[0].match.state, "ai_match_confident")
        self.assertEqual(body.items[0].match.match_count, 3)
        list_sql, list_params = session.calls[0]
        count_sql, count_params = session.calls[1]
        self.assertIn("transaction_email_match", count_sql)
        self.assertIn("match_state", count_sql)
        self.assertEqual(count_params["match_state"], "ai_match_confident")
        self.assertIn("match_count", list_sql)
        self.assertEqual(list_params["match_state"], "ai_match_confident")
        self.assertEqual(list_params["only_unmoved_match"], False)

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_endpoint_filters_by_match_state(self, get_session_mock):
        #R070-T02
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(
            rows=[
                _Result(rows=[]),
                _Result(scalar=0),
            ]
        )
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "only_unclassified": "false",
                          "match_state": "human_confirmed_ai_match", "only_unmoved_match": "true",
                          "limit": "10", "offset": "0"}
        )
        body = endpoint(
            request=request,
            search="",
            status="",
            only_unclassified=False,
            match_state="human_confirmed_ai_match",
            only_unmoved_match=True,
            include_total=True,
            count_only=False,
            limit=10,
            offset=0,
        )
        self.assertEqual(body.total, 0)
        list_sql, list_params = session.calls[0]
        self.assertIn("match_state", list_sql)
        self.assertIn("only_unmoved_match", list_sql)
        self.assertEqual(list_params["match_state"], "human_confirmed_ai_match")
        self.assertEqual(list_params["only_unmoved_match"], True)

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_endpoint_filters_unmatched_match_state(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(rows=[_Result(rows=[]), _Result(scalar=0)])
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "only_unclassified": "false",
                          "match_state": "unmatched", "limit": "10", "offset": "0"}
        )
        endpoint(
            request=request,
            search="",
            status="",
            only_unclassified=False,
            match_state="unmatched",
            only_unmoved_match=False,
            include_total=True,
            count_only=False,
            limit=10,
            offset=0,
        )
        list_sql, list_params = session.calls[0]
        self.assertIn("unmatched", list_sql)
        self.assertIn("ai_no_match_found", list_sql)
        self.assertEqual(list_params["match_state"], "unmatched")

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_endpoint_filters_no_email_match_state(self, get_session_mock):
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(rows=[_Result(rows=[]), _Result(scalar=0)])
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "only_unclassified": "false",
                          "match_state": "no_email", "limit": "10", "offset": "0"}
        )
        endpoint(
            request=request,
            search="",
            status="",
            only_unclassified=False,
            match_state="no_email",
            only_unmoved_match=False,
            include_total=True,
            count_only=False,
            limit=10,
            offset=0,
        )
        list_sql, list_params = session.calls[0]
        self.assertIn("no_email", list_sql)
        self.assertIn("selected_by = 'human'", list_sql)
        self.assertEqual(list_params["match_state"], "no_email")

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_count_only_runs_count_without_list(self, get_session_mock):
        #R072-T01
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(rows=[_Result(scalar=1074)])
        get_session_mock.return_value = _SessionContext(session)
        request = SimpleNamespace(
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "only_unclassified": "true",
                          "count_only": "true", "limit": "1", "offset": "0"},
        )
        body = endpoint(
            request=request,
            search="",
            status="",
            only_unclassified=True,
            match_state="",
            only_unmoved_match=False,
            include_total=True,
            count_only=True,
            limit=1,
            offset=0,
        )
        self.assertEqual(body.total, 1074)
        self.assertEqual(body.items, [])
        self.assertEqual(len(session.calls), 1)
        self.assertIn("COUNT", session.calls[0][0].upper())

    @patch("teller.teller_classification_api.get_session")
    def test_transactions_include_total_false_skips_count_query(self, get_session_mock):
        #R072-T02
        app = create_app()
        endpoint = self._route_endpoint(app, "/v1/transactions", "GET")
        session = _FakeSession(
            rows=[
                _Result(
                    rows=[
                        {
                            "transaction_id": "txn_1",
                            "account_id": "acc_1",
                            "institution_id": None,
                            "account_last_four": None,
                            "date": "2026-01-01",
                            "amount": "5.00",
                            "description": "Coffee",
                            "status": "posted",
                            "transaction_type_code": "card_payment",
                            "teller_category": None,
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
            headers={"x-teller-write-token": "test-write-token"},
            query_params={"search": "", "status": "", "only_unclassified": "false",
                          "include_total": "false", "limit": "150", "offset": "0"},
        )
        body = endpoint(
            request=request,
            search="",
            status="",
            only_unclassified=False,
            match_state="",
            only_unmoved_match=False,
            include_total=False,
            count_only=False,
            limit=150,
            offset=0,
        )
        self.assertEqual(len(session.calls), 1)
        self.assertIn("LIMIT", session.calls[0][0])
        self.assertEqual(body.total, 1)
        self.assertEqual(len(body.items), 1)


if __name__ == "__main__":
    unittest.main()
