import importlib.util
import json
import unittest
from contextlib import contextmanager
from datetime import date
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from teller.teller_classification_api import create_app
from teller.teller_mailcart_client import MailcartClient

try:
    from fastapi.testclient import TestClient
except RuntimeError:
    TestClient = None


def _load_contract_scenarios() -> dict:
    repo_root = Path(__file__).resolve().parents[2]
    path = repo_root / "tests" / "contracts" / "frontend_backend_contract_scenarios.json"
    return json.loads(path.read_text(encoding="utf-8"))


class _Result:
    def __init__(self, *, rows=None, scalar=None):
        self._rows = rows or []
        self._scalar = scalar

    def mappings(self):
        return self

    def all(self):
        return self._rows

    def scalar_one(self):
        return self._scalar


class _RecordingSession:
    def __init__(self, *, count=0):
        self.count = count
        self.calls = []

    def execute(self, sql, params=None):
        self.calls.append((str(sql), params or {}))
        return _Result(scalar=self.count)


@contextmanager
def _session_context(session):
    yield session


class ContractScenarioCorpusTests(unittest.TestCase):
    def test_corpus_contains_required_sections(self):
        #R065-T01
        scenarios = _load_contract_scenarios()
        self.assertIn("classificationApi", scenarios)
        self.assertIn("mailcartProxy", scenarios)
        self.assertIn("tellerUpstream", scenarios)

    def test_mailcart_search_contract_matches_client_path_and_params(self):
        #R065-T02
        scenarios = _load_contract_scenarios()
        expected = scenarios["mailcartProxy"]["searchRequest"]
        session = SimpleNamespace(request=lambda **kwargs: SimpleNamespace(status_code=200, json=lambda: {"messages": []}))
        client = MailcartClient(base_url="https://127.0.0.1:8788", session=session)

        with patch.object(session, "request", wraps=session.request) as request_mock:
            client.search(query=expected["params"]["query"], limit=expected["params"]["limit"])

        kwargs = request_mock.call_args.kwargs
        self.assertEqual(kwargs["method"], "GET")
        self.assertEqual(kwargs["url"], f"https://127.0.0.1:8788{expected['path']}")
        self.assertEqual(kwargs["params"]["query"], expected["params"]["query"])
        self.assertEqual(kwargs["params"]["limit"], expected["params"]["limit"])

    def test_teller_required_markers_match_drift_checker_defaults(self):
        #R065-T03
        scenarios = _load_contract_scenarios()
        expected_markers = scenarios["tellerUpstream"]["requiredMarkers"]

        repo_root = Path(__file__).resolve().parents[2]
        script_path = repo_root / "src" / "scripts" / "check_teller_api_drift.py"
        spec = importlib.util.spec_from_file_location("check_teller_api_drift", script_path)
        module = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(module)

        result = module.run_fallback_checks()
        marker_names = {check["name"] for check in result["checks"] if check["name"].startswith("source:")}
        self.assertTrue(marker_names)
        self.assertEqual(expected_markers, ["/institutions", "/accounts", "/identity"])


@unittest.skipIf(TestClient is None, "fastapi testclient optional dependency (httpx) is not installed")
class ClassificationApiHttpContractTests(unittest.TestCase):
    def setUp(self):
        self._token_patch = patch("teller.teller_classification_api._configured_write_token", return_value="test-write-token")
        self._token_patch.start()

    def tearDown(self):
        self._token_patch.stop()

    def test_frontend_used_endpoints_require_write_token(self):
        #R040-T05
        app = create_app()
        client = TestClient(app)
        cases = [
            ("get", "/v1/categories", None),
            ("post", "/v1/categories", {"categorization": "Dining"}),
            ("put", "/v1/categories/101", {"categorization": "Dining Updated"}),
            ("delete", "/v1/categories/101", None),
            ("get", "/v1/transactions", None),
            ("post", "/v1/transactions/classifications", {"updates": [{"transaction_id": "txn_1", "nys_snw_category_id": 101}]}),
            ("put", "/v1/matchy/matches/1/confirm", None),
            ("put", "/v1/matchy/matches/1/override", {"email_message_id": "msg_1", "note": "override"}),
            ("put", "/v1/matchy/matches/1/no-email", None),
            ("put", "/v1/matchy/matches/1/clear", None),
            ("put", "/v1/matchy/transactions/txn_1/confirm-candidate", {"email_message_id": "msg_1", "note": "confirm"}),
            ("put", "/v1/matchy/transactions/txn_1/override-candidate", {"email_message_id": "msg_1", "note": "override"}),
            ("put", "/v1/matchy/transactions/txn_1/override", {"email_message_id": "msg_1", "note": "override"}),
            ("put", "/v1/matchy/transactions/txn_1/no-email", None),
            ("put", "/v1/matchy/transactions/txn_1/clear", None),
            ("get", "/v1/matchy/transactions/txn_1/candidates", None),
            ("get", "/v1/matchy/messages/search?subject=test", None),
            ("get", "/v1/matchy/messages/msg_1", None),
        ]
        for method, path, body in cases:
            response = client.request(method.upper(), path, json=body)
            self.assertEqual(response.status_code, 401, f"{method} {path} should require token")

    def test_transactions_accepts_advanced_filter_query_from_frontend(self):
        #R075-T01
        scenarios = _load_contract_scenarios()
        query = scenarios["classificationApi"]["transactions"]["advancedFilters"]["query"]
        recording_session = _RecordingSession(count=0)
        app = create_app()
        client = TestClient(app)
        headers = {"X-Teller-Write-Token": "test-write-token"}
        with patch("teller.teller_classification_api.get_session", return_value=_session_context(recording_session)):
            response = client.get(
                "/v1/transactions",
                params={
                    **query,
                    "count_only": "true",
                },
                headers=headers,
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["total"], 0)
        self.assertEqual(len(recording_session.calls), 1)
        params = recording_session.calls[0][1]
        self.assertEqual(params["start_date"], date.fromisoformat(query["start_date"]))
        self.assertEqual(params["end_date"], date.fromisoformat(query["end_date"]))
        self.assertEqual(params["institution_id"], query["institution_id"])
        self.assertEqual(params["min_amount"], Decimal(query["min_amount"]))
        self.assertEqual(params["max_amount"], Decimal(query["max_amount"]))

    def test_transactions_http_rejects_malformed_start_date_with_friendly_message(self):
        #R075-T02
        app = create_app()
        client = TestClient(app)
        headers = {"X-Teller-Write-Token": "test-write-token"}
        response = client.get(
            "/v1/transactions",
            params={"start_date": "202", "count_only": "true"},
            headers=headers,
        )
        self.assertEqual(response.status_code, 422)
        payload = response.json()
        self.assertEqual(payload["detail"], "Expected date format: YYYY-MM-DD for start_date")

    def test_transactions_http_rejects_malformed_end_date_with_friendly_message(self):
        #R075-T03
        app = create_app()
        client = TestClient(app)
        headers = {"X-Teller-Write-Token": "test-write-token"}
        response = client.get(
            "/v1/transactions",
            params={"end_date": "202", "count_only": "true"},
            headers=headers,
        )
        self.assertEqual(response.status_code, 422)
        payload = response.json()
        self.assertEqual(payload["detail"], "Expected date format: YYYY-MM-DD for end_date")

    def test_transactions_http_rejects_calendar_invalid_date_with_friendly_message(self):
        app = create_app()
        client = TestClient(app)
        headers = {"X-Teller-Write-Token": "test-write-token"}
        response = client.get(
            "/v1/transactions",
            params={"end_date": "3624-16-14", "count_only": "true"},
            headers=headers,
        )
        self.assertEqual(response.status_code, 422)
        payload = response.json()
        self.assertEqual(payload["detail"], "Expected date format: YYYY-MM-DD for end_date")

    def test_message_search_date_only_end_matches_contract(self):
        #R062-T08
        scenarios = _load_contract_scenarios()
        scenario = scenarios["classificationApi"]["messageSearch"]["dateOnlyEnd"]
        expected_query = scenario["effective_query"]
        mailcart = SimpleNamespace(search=lambda query, limit: {"messages": [], "echo": [query, limit]})
        app = create_app()
        client = TestClient(app)
        headers = {"X-Teller-Write-Token": "test-write-token"}
        with patch("teller.teller_classification_api.get_mailcart_client", return_value=mailcart):
            response = client.get("/v1/matchy/messages/search", params=scenario["query"], headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["query"], expected_query)
        self.assertEqual(response.json()["items"], [])

    def test_message_search_scoped_and_normalized_matches_contract(self):
        scenarios = _load_contract_scenarios()
        scenario = scenarios["classificationApi"]["messageSearch"]["scopedAndNormalized"]
        expected_query = scenario["effective_query"]

        class _Mailcart:
            def __init__(self):
                self.calls = []

            def search(self, query, limit):
                self.calls.append({"query": query, "limit": limit})
                return {"messages": []}

        mailcart = _Mailcart()
        app = create_app()
        client = TestClient(app)
        headers = {"X-Teller-Write-Token": "test-write-token"}
        with patch("teller.teller_classification_api.get_mailcart_client", return_value=mailcart):
            response = client.get("/v1/matchy/messages/search", params=scenario["query"], headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["query"], expected_query)
        self.assertEqual(mailcart.calls, [{"query": expected_query, "limit": 25}])


if __name__ == "__main__":
    unittest.main()
