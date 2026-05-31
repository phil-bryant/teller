#!/usr/bin/env python3
import builtins
import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path


def _stub_teller_modules() -> dict[str, object]:
    original: dict[str, object] = {}

    for name in [
        "requests",
        "structlog",
        "dotenv",
        "teller",
        "teller.teller_object",
        "teller.teller_account",
        "teller.teller_account_identities",
        "teller.teller_identity",
        "teller.teller_transaction",
    ]:
        original[name] = sys.modules.get(name)

    requests_mod = types.ModuleType("requests")
    structlog_mod = types.ModuleType("structlog")
    dotenv_mod = types.ModuleType("dotenv")
    teller_pkg = types.ModuleType("teller")
    teller_object_mod = types.ModuleType("teller.teller_object")
    teller_account_mod = types.ModuleType("teller.teller_account")
    teller_account_identities_mod = types.ModuleType("teller.teller_account_identities")
    teller_identity_mod = types.ModuleType("teller.teller_identity")
    teller_transaction_mod = types.ModuleType("teller.teller_transaction")

    class _Dummy:
        def __init__(self, *_args, **_kwargs):
            pass

    class _DummyObject:
        @staticmethod
        def set_api_client(_client):
            return None

    class _StructlogLogger:
        def info(self, *_args, **_kwargs):
            return None

        def warning(self, *_args, **_kwargs):
            return None

    def _fake_get_logger():
        return _StructlogLogger()

    def _fake_make_filtering_bound_logger(_level):
        return _StructlogLogger

    def _fake_configure(**_kwargs):
        return None

    requests_mod.get = lambda *_args, **_kwargs: None
    structlog_mod.get_logger = _fake_get_logger
    structlog_mod.make_filtering_bound_logger = _fake_make_filtering_bound_logger
    structlog_mod.configure = _fake_configure
    dotenv_mod.load_dotenv = lambda *_args, **_kwargs: None

    teller_object_mod.TellerObject = _DummyObject
    teller_account_mod.TellerAccount = _Dummy
    teller_account_identities_mod.TellerAccountIdentities = _Dummy
    teller_identity_mod.TellerIdentity = _Dummy
    teller_transaction_mod.TellerTransaction = _Dummy

    teller_pkg.teller_object = teller_object_mod
    teller_pkg.teller_account = teller_account_mod
    teller_pkg.teller_account_identities = teller_account_identities_mod
    teller_pkg.teller_identity = teller_identity_mod
    teller_pkg.teller_transaction = teller_transaction_mod

    sys.modules["requests"] = requests_mod
    sys.modules["structlog"] = structlog_mod
    sys.modules["dotenv"] = dotenv_mod
    sys.modules["teller"] = teller_pkg
    sys.modules["teller.teller_object"] = teller_object_mod
    sys.modules["teller.teller_account"] = teller_account_mod
    sys.modules["teller.teller_account_identities"] = teller_account_identities_mod
    sys.modules["teller.teller_identity"] = teller_identity_mod
    sys.modules["teller.teller_transaction"] = teller_transaction_mod
    return original


def _restore_modules(original: dict[str, object]) -> None:
    for name, value in original.items():
        if value is None:
            sys.modules.pop(name, None)
        else:
            sys.modules[name] = value


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "07_fetch_teller_api_data.py"
    spec = importlib.util.spec_from_file_location("fetch_teller_api_data", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load 14_fetch_teller_api_data module")

    module = importlib.util.module_from_spec(spec)
    original = _stub_teller_modules()
    try:
        spec.loader.exec_module(module)
    finally:
        _restore_modules(original)
    return module


class EnrollmentContextDiscoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.teller_dir = Path(self.temp_dir.name)
        self.module.TELLER_DIR = self.teller_dir

    def _write_token(self, filename: str, token: str) -> None:
        payload = {"current": token}
        (self.teller_dir / filename).write_text(json.dumps(payload), encoding="utf-8")

    def test_build_contexts_uses_suffix_tokens_without_default_token(self) -> None:
        self._write_token("auth_token_chase.json", "token-chase")
        (self.teller_dir / "enrollment_id_chase.txt").write_text("enr_chase\n", encoding="utf-8")

        contexts = self.module._build_enrollment_contexts("")
        self.assertEqual(len(contexts), 1)
        self.assertEqual(contexts[0]["institution_id"], "chase")
        self.assertEqual(contexts[0]["enrollment_id"], "enr_chase")
        self.assertEqual(contexts[0]["token"], "token-chase")
        self.assertEqual(contexts[0]["source"], "suffix")

    def test_build_contexts_keeps_default_context_when_token_present(self) -> None:
        self._write_token("auth_token.json", "token-default")
        (self.teller_dir / "enrollment_id.txt").write_text("enr_default\n", encoding="utf-8")

        contexts = self.module._build_enrollment_contexts("")
        self.assertEqual(len(contexts), 1)
        self.assertEqual(contexts[0]["token"], "token-default")
        self.assertEqual(contexts[0]["source"], "default")

    def test_dedupe_contexts_prefers_last_duplicate_entry(self) -> None:
        contexts = self.module._dedupe_contexts(
            [
                {"enrollment_id": "enr_1", "token": "token-old", "institution_id": "ins_1", "source": "metadata"},
                {"enrollment_id": "enr_1", "token": "token-new", "institution_id": "ins_1", "source": "suffix"},
            ]
        )
        self.assertEqual(len(contexts), 1)
        self.assertEqual(contexts[0]["token"], "token-new")
        self.assertEqual(contexts[0]["source"], "suffix")

    def test_build_contexts_filters_by_institution(self) -> None:
        self._write_token("auth_token_bank_a.json", "token-a")
        self._write_token("auth_token_bank_b.json", "token-b")
        (self.teller_dir / "enrollment_id_bank_a.txt").write_text("enr_a\n", encoding="utf-8")
        (self.teller_dir / "enrollment_id_bank_b.txt").write_text("enr_b\n", encoding="utf-8")

        contexts = self.module._build_enrollment_contexts("bank_b")
        self.assertEqual(len(contexts), 1)
        self.assertEqual(contexts[0]["institution_id"], "bank_b")
        self.assertEqual(contexts[0]["token"], "token-b")
        self.assertEqual(contexts[0]["source"], "suffix")

    def test_load_suffix_contexts_skips_malformed_empty_suffix_filename(self) -> None:
        self._write_token("auth_token_.json", "token-bad")
        self._write_token("auth_token_bank_valid.json", "token-good")
        (self.teller_dir / "enrollment_id_bank_valid.txt").write_text("enr_valid\n", encoding="utf-8")

        contexts = self.module._load_suffix_contexts()
        self.assertEqual(len(contexts), 1)
        self.assertEqual(contexts[0]["institution_id"], "bank_valid")
        self.assertEqual(contexts[0]["token"], "token-good")


class TellerApiClientRequestTimeoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_get_passes_explicit_timeout_to_requests(self) -> None:
        #R005-T04
        class _Response:
            status_code = 200

            @staticmethod
            def json():
                return {}

        captured = {}

        def _fake_get(url, params=None, timeout=None, **kwargs):
            captured["url"] = url
            captured["params"] = params
            captured["timeout"] = timeout
            captured["kwargs"] = kwargs
            return _Response()

        self.module.requests.get = _fake_get

        client = self.module.TellerAPIClient.__new__(self.module.TellerAPIClient)
        client.kwargs = {"auth": ("token-value", ""), "headers": {}, "verify": True}
        client._repair_enrollment = lambda: False

        payload = self.module.TellerAPIClient.get(client, "https://api.teller.io/test", {"from_id": "txn_1"})
        self.assertEqual(payload, {})
        self.assertEqual(captured["timeout"], self.module.REQUEST_TIMEOUT_SECONDS)
        self.assertEqual(captured["params"], {"from_id": "txn_1"})

    def test_get_raises_teller_api_error_for_429_without_repair_retry(self) -> None:
        #R040-T01
        class _Response:
            status_code = 429
            text = "rate-limited"

            @staticmethod
            def json():
                return {"error": {"code": "rate_limited", "message": "slow down"}}

        calls = []

        def _fake_get(url, params=None, timeout=None, **kwargs):
            calls.append((url, params, timeout, kwargs))
            return _Response()

        self.module.requests.get = _fake_get
        client = self.module.TellerAPIClient.__new__(self.module.TellerAPIClient)
        client.kwargs = {"auth": ("token-value", ""), "headers": {}, "verify": True}
        repair_calls = []
        client._repair_enrollment = lambda: repair_calls.append("called") or True

        with self.assertRaises(self.module.TellerAPIError) as exc:
            self.module.TellerAPIClient.get(client, "https://api.teller.io/test", {"from_id": "txn_1"})

        self.assertEqual(exc.exception.status_code, 429)
        self.assertEqual(exc.exception.code, "rate_limited")
        self.assertEqual(exc.exception.message, "slow down")
        self.assertEqual(len(calls), 1)
        self.assertEqual(repair_calls, [])

    def test_fetch_all_transactions_uses_from_id_pagination(self) -> None:
        class _FakeClient:
            def __init__(self):
                self.calls = []

            def get(self, _url, params=None):
                self.calls.append(params or {})
                if params is None:
                    return [{"id": "txn_1", "date": "2026-01-03"}, {"id": "txn_2", "date": "2026-01-02"}]
                if params.get("from_id") == "txn_2":
                    return [{"id": "txn_3", "date": "2026-01-01"}]
                return []

        client = _FakeClient()
        txns = self.module._fetch_all_transactions(client, "https://api.teller.io/txns")
        self.assertEqual([txn["id"] for txn in txns], ["txn_1", "txn_2", "txn_3"])
        self.assertEqual(client.calls, [{}, {"from_id": "txn_2"}, {"from_id": "txn_3"}])

    def test_fetch_all_transactions_raises_on_mid_pagination_rate_limit(self) -> None:
        #R040-T02
        class _FakeClient:
            def __init__(self, module):
                self.module = module
                self.calls = []

            def get(self, _url, params=None):
                self.calls.append(params or {})
                if params is None:
                    return [{"id": "txn_1", "date": "2026-01-03"}, {"id": "txn_2", "date": "2026-01-02"}]
                if params.get("from_id") == "txn_2":
                    raise self.module.TellerAPIError(
                        message="slow down",
                        code="rate_limited",
                        status_code=429,
                    )
                return []

        client = _FakeClient(self.module)
        with self.assertRaises(self.module.TellerAPIError) as exc:
            self.module._fetch_all_transactions(client, "https://api.teller.io/txns")
        self.assertEqual(exc.exception.status_code, 429)
        self.assertEqual(exc.exception.code, "rate_limited")
        self.assertEqual(client.calls, [{}, {"from_id": "txn_2"}])

    def test_get_retries_once_for_disconnected_enrollment_code(self) -> None:
        #R010-T01
        class _Response:
            def __init__(self, status_code, payload, text):
                self.status_code = status_code
                self._payload = payload
                self.text = text

            def json(self):
                return self._payload

        calls = []

        def _fake_get(url, params=None, timeout=None, **kwargs):
            calls.append((url, params, timeout, kwargs))
            if len(calls) == 1:
                return _Response(
                    404,
                    {"error": {"code": "enrollment.disconnected", "message": "reconnect required"}},
                    "reconnect required",
                )
            return _Response(200, {"ok": True}, "")

        self.module.requests.get = _fake_get
        client = self.module.TellerAPIClient.__new__(self.module.TellerAPIClient)
        client.kwargs = {"auth": ("token-value", ""), "headers": {}, "verify": True}
        repair_calls = []
        client._repair_enrollment = lambda: repair_calls.append("called") or True

        payload = self.module.TellerAPIClient.get(client, "https://api.teller.io/test", {"from_id": "txn_1"})
        self.assertEqual(payload, {"ok": True})
        self.assertEqual(len(calls), 2)
        self.assertEqual(repair_calls, ["called"])

    def test_fetch_all_transactions_raises_on_repeated_cursor(self) -> None:
        class _FakeClient:
            def get(self, _url, params=None):
                if params is None:
                    return [{"id": "txn_1", "date": "2026-01-03"}, {"id": "txn_2", "date": "2026-01-02"}]
                if params.get("from_id") == "txn_2":
                    return [{"id": "txn_2", "date": "2026-01-01"}]
                return []

        with self.assertRaises(self.module.TellerAPIError) as exc:
            self.module._fetch_all_transactions(_FakeClient(), "https://api.teller.io/txns")
        self.assertEqual(exc.exception.code, "transactions.pagination.repeated_cursor")

    def test_fetch_all_transactions_raises_when_max_pages_exceeded(self) -> None:
        class _FakeClient:
            def get(self, _url, params=None):
                if params is None:
                    return [{"id": "txn_1", "date": "2026-01-03"}]
                if params.get("from_id") == "txn_1":
                    return [{"id": "txn_2", "date": "2026-01-02"}]
                return []

        previous = self.module.os.environ.get("TELLER_TXN_MAX_PAGES")
        self.module.os.environ["TELLER_TXN_MAX_PAGES"] = "1"
        try:
            with self.assertRaises(self.module.TellerAPIError) as exc:
                self.module._fetch_all_transactions(_FakeClient(), "https://api.teller.io/txns")
        finally:
            if previous is None:
                self.module.os.environ.pop("TELLER_TXN_MAX_PAGES", None)
            else:
                self.module.os.environ["TELLER_TXN_MAX_PAGES"] = previous
        self.assertEqual(exc.exception.code, "transactions.pagination.max_pages_exceeded")

    def test_repair_enrollment_fails_fast_in_non_interactive_session(self) -> None:
        class _FakeTTY:
            @staticmethod
            def isatty():
                return False

        client = self.module.TellerAPIClient.__new__(self.module.TellerAPIClient)
        client._enrollment_id = "enr_123"
        original_stdin = self.module.sys.stdin
        original_stdout = self.module.sys.stdout
        self.module.sys.stdin = _FakeTTY()
        self.module.sys.stdout = _FakeTTY()
        try:
            with self.assertRaises(self.module.TellerAPIError) as exc:
                self.module.TellerAPIClient._repair_enrollment(client)
        finally:
            self.module.sys.stdin = original_stdin
            self.module.sys.stdout = original_stdout
        self.assertEqual(exc.exception.code, "enrollment.disconnected.manual_repair_required")

    def test_repair_enrollment_prompts_and_reloads_when_interactive(self) -> None:
        class _FakeTTYIn:
            @staticmethod
            def isatty():
                return True

        class _FakeTTYOut:
            def __init__(self):
                self.buffer = []

            @staticmethod
            def isatty():
                return True

            def write(self, value):
                self.buffer.append(value)
                return len(value)

            def flush(self):
                return None

        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        script_dir = Path(temp_dir.name)
        launcher = script_dir / "10_run_classification_macos_ui.sh"
        launcher.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        launcher.chmod(0o755)

        popen_calls = []
        input_calls = []
        load_auth_calls = []
        original_file = self.module.__file__
        original_stdin = self.module.sys.stdin
        original_stdout = self.module.sys.stdout
        original_popen = self.module.subprocess.Popen
        original_input = builtins.input

        client = self.module.TellerAPIClient.__new__(self.module.TellerAPIClient)
        client._enrollment_id = "enr_123"
        client._load_auth = lambda: load_auth_calls.append("called")

        self.module.__file__ = str(script_dir / "07_fetch_teller_api_data.py")
        self.module.sys.stdin = _FakeTTYIn()
        self.module.sys.stdout = _FakeTTYOut()
        self.module.subprocess.Popen = lambda args, env=None: popen_calls.append((args, env))
        builtins.input = lambda _prompt: input_calls.append("prompted") or ""
        try:
            repaired = self.module.TellerAPIClient._repair_enrollment(client)
        finally:
            self.module.__file__ = original_file
            self.module.sys.stdin = original_stdin
            self.module.sys.stdout = original_stdout
            self.module.subprocess.Popen = original_popen
            builtins.input = original_input

        self.assertTrue(repaired)
        self.assertEqual(len(popen_calls), 1)
        self.assertEqual(len(input_calls), 1)
        self.assertEqual(len(load_auth_calls), 1)


class TellerApiMainIsolationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()

    def test_main_continues_after_single_context_rate_limited_failure(self) -> None:
        #R025-T02
        contexts = [
            {"institution_id": "bank_a", "enrollment_id": "enr_a", "token": "token-a", "source": "suffix"},
            {"institution_id": "bank_b", "enrollment_id": "enr_b", "token": "token-b", "source": "suffix"},
        ]
        fetch_calls = []
        persisted = {}

        class _Args:
            debug = False
            dry_run = False
            institution_id = ""

        original_argv = list(self.module.sys.argv)
        original_build_contexts = self.module._build_enrollment_contexts
        original_fetch_context_data = self.module._fetch_context_data
        original_client = self.module.TellerAPIClient
        original_parse_args = self.module.argparse.ArgumentParser.parse_args
        original_db_module = sys.modules.get("teller.teller_db")
        original_persist_module = sys.modules.get("teller.teller_persist")
        self.addCleanup(lambda: setattr(self.module, "_build_enrollment_contexts", original_build_contexts))
        self.addCleanup(lambda: setattr(self.module, "_fetch_context_data", original_fetch_context_data))
        self.addCleanup(lambda: setattr(self.module, "TellerAPIClient", original_client))
        self.addCleanup(
            lambda: setattr(self.module.argparse.ArgumentParser, "parse_args", original_parse_args)
        )
        self.addCleanup(lambda: setattr(self.module.sys, "argv", original_argv))

        def _restore_module(name, original):
            if original is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = original

        self.addCleanup(lambda: _restore_module("teller.teller_db", original_db_module))
        self.addCleanup(lambda: _restore_module("teller.teller_persist", original_persist_module))

        def _fake_build_contexts(_institution_id):
            return contexts

        def _fake_fetch_context_data(client, _institution_id):
            fetch_calls.append(client._enrollment_id)
            if client._enrollment_id == "enr_a":
                raise self.module.TellerAPIError(message="slow down", code="rate_limited", status_code=429)
            identities = [{"account": {"id": "acct_1", "institution": {"id": "bank_b", "name": "Bank B"}}}]
            return identities, {"acct_1": [{"id": "txn_1", "date": "2026-01-01"}]}, {}

        class _FakeClient:
            def __init__(self, auth_token="", enrollment_id=""):
                self._auth_token = auth_token
                self._enrollment_id = enrollment_id

        class _FakeSession:
            def rollback(self):
                return None

            def close(self):
                return None

        fake_db_module = types.ModuleType("teller.teller_db")
        fake_persist_module = types.ModuleType("teller.teller_persist")
        fake_db_module.get_session = lambda: _FakeSession()

        def _persist_all(_session, raw_identities, raw_transactions_by_account, raw_balances_by_account):
            persisted["identities"] = raw_identities
            persisted["tx"] = raw_transactions_by_account
            persisted["bal"] = raw_balances_by_account

        fake_persist_module.persist_all = _persist_all
        sys.modules["teller.teller_db"] = fake_db_module
        sys.modules["teller.teller_persist"] = fake_persist_module

        self.module._build_enrollment_contexts = _fake_build_contexts
        self.module._fetch_context_data = _fake_fetch_context_data
        self.module.TellerAPIClient = _FakeClient
        self.module.argparse.ArgumentParser.parse_args = lambda _parser: _Args()
        self.module.sys.argv = ["07_fetch_teller_api_data.py"]

        self.module.main()

        self.assertEqual(fetch_calls, ["enr_a", "enr_b"])
        self.assertEqual(len(persisted["identities"]), 1)
        self.assertEqual(persisted["identities"][0]["account"]["id"], "acct_1")
        self.assertEqual(persisted["tx"]["acct_1"][0]["id"], "txn_1")


if __name__ == "__main__":
    unittest.main()
