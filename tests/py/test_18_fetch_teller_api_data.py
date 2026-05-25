#!/usr/bin/env python3
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
    script_path = repo_root / "18_fetch_teller_api_data.py"
    spec = importlib.util.spec_from_file_location("fetch_teller_api_data", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load 13_fetch_teller_api_data module")

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


if __name__ == "__main__":
    unittest.main()
