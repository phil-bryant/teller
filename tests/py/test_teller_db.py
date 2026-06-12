import os
import sys
import unittest
from unittest.mock import MagicMock, patch

from teller import teller_db
from teller.teller_db_profile import ResolvedProfile


_DB_ENV_KEYS = (
    "TELLER_DB_PROFILE",
    "TELLER_DB_PROFILE_FILE",
    "TELLER_DB_HOST",
    "TELLER_DB_PORT",
    "TELLER_DB_NAME",
    "TELLER_DB_USER",
    "TELLER_DB_PASSWORD",
    "TELLER_DB_ROLE",
    "TELLER_DB_SSLMODE",
    "TELLER_DB_SEARCH_PATH",
    "TELLER_DB_SQLITE_PATH",
    "TELLER_DB_SQLCIPHER_KEY",
    "TELLER_PSA_ITEM",
)

_LOCAL_PROFILE = ResolvedProfile(
    name="local", host="localhost", port=5432, dbname="prod", user="teller",
    onepsa_item="localhost_postgres_teller", search_path="teller,classy,matchy",
    runtime_role="teller_write", sslmode="disable", target="local", sqlite_path="", sqlcipher_key="",
)

_SUPABASE_PROFILE = ResolvedProfile(
    name="supabase", host="db.example.supabase.co", port=5432, dbname="postgres",
    user="postgres", onepsa_item="eggnest_supabase", search_path="teller,classy,matchy",
    runtime_role="", sslmode="require", target="managed", sqlite_path="", sqlcipher_key="",
)

_SQLITE_PROFILE = ResolvedProfile(
    name="sqlite", host="", port=0, dbname="", user="",
    onepsa_item="", search_path="teller", runtime_role="",
    sslmode="disable", target="sqlite", sqlite_path="/tmp/teller-test.sqlite3", sqlcipher_key="k",
)


class _IsolatedEnvTest(unittest.TestCase):
    #R030: Prepare isolated environment for engine-construction tests.
    def setUp(self):
        self._saved_env = {key: os.environ.pop(key) for key in _DB_ENV_KEYS if key in os.environ}
        teller_db._engine = None

    #R030: Restore isolated environment after engine-construction tests.
    def tearDown(self):
        for key in _DB_ENV_KEYS:
            os.environ.pop(key, None)
        for key, value in self._saved_env.items():
            os.environ[key] = value
        teller_db._engine = None


class PasswordResolutionTests(_IsolatedEnvTest):
    # #R025: TELLER_DB_PASSWORD short-circuits libonepsa.
    def test_env_password_wins(self):
        #R025-T01: With `TELLER_DB_PASSWORD` set, verify the env value is returned and libonepsa is not invoked.
        os.environ["TELLER_DB_PASSWORD"] = "from-env"  # pragma: allowlist secret
        with patch("teller.teller_db._read_password_from_onepsa") as fake_onepsa:
            fake_onepsa.side_effect = AssertionError("libonepsa must not be called")
            self.assertEqual(teller_db._read_password(_LOCAL_PROFILE), "from-env")
            fake_onepsa.assert_not_called()

    # #R025: Empty onepsa_item with no env password raises a clear error.
    def test_missing_onepsa_item_raises(self):
        #R025-T02: With `TELLER_DB_PASSWORD` unset and a profile lacking `1psa_item`, verify a `RuntimeError` is raised.
        empty_profile = ResolvedProfile(
            name="noitem", host="h", port=5432, dbname="d", user="u",
            onepsa_item="", search_path="teller", runtime_role="",
            sslmode="disable", target="local", sqlite_path="", sqlcipher_key="",
        )
        with self.assertRaises(RuntimeError):
            teller_db._read_password(empty_profile)

    def test_onepsa_password_command_quotes_item_name(self):
        #R025-T03: onepsa password command safely quotes item names.
        command = teller_db._onepsa_password_command("item with spaces")
        self.assertIn("1psa -p", command)
        self.assertIn("'item with spaces'", command)

    def test_read_password_from_onepsa_raises_when_error_pointer_is_set(self):
        #R025-T04: libonepsa error pointer is surfaced as RuntimeError.
        fake_lib = MagicMock()
        fake_lib.OnepsaGetField.side_effect = lambda *_args: None

        #R025: nested helper function tag
        def _set_err(_item, _field, err_ptr):
            err_ptr._obj.value = b"boom"
            return None

        fake_lib.OnepsaGetField.side_effect = _set_err
        with patch.object(teller_db.ctypes, "CDLL", return_value=fake_lib):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                teller_db._read_password_from_onepsa("item")

    def test_read_password_from_onepsa_raises_on_null_pointer_without_error(self):
        #R025-T05: null libonepsa pointer without error is rejected.
        fake_lib = MagicMock()

        #R025: nested helper function tag
        def _null_without_error(_item, _field, err_ptr):
            err_ptr._obj.value = None
            return None

        fake_lib.OnepsaGetField.side_effect = _null_without_error
        with patch.object(teller_db.ctypes, "CDLL", return_value=fake_lib):
            with self.assertRaisesRegex(RuntimeError, "null password"):
                teller_db._read_password_from_onepsa("item")

    def test_read_password_falls_back_to_env_fields_when_onepsa_fails(self):
        #R025-T06: password resolution falls back to profile env fields when onepsa read fails.
        with (
            patch("teller.teller_db._read_password_from_onepsa", side_effect=RuntimeError("unavailable")),
            patch("teller.teller_db_profile._read_env_file_fields", return_value={"password": "from-env-file"}),  # pragma: allowlist secret
        ):
            password = teller_db._read_password(_LOCAL_PROFILE)
        self.assertEqual(password, "from-env-file")

    def test_read_password_raises_keyboard_interrupt_from_onepsa(self):
        #R025-T07: keyboard interrupts during onepsa lookup are re-raised.
        with patch("teller.teller_db._read_password_from_onepsa", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                teller_db._read_password(_LOCAL_PROFILE)


class EngineConstructionTests(_IsolatedEnvTest):
    # #R030: Engine is built once and cached.
    def test_engine_is_cached(self):
        #R030-T01: Patch `create_engine` and verify two `get_engine()` calls produce one engine and one underlying call.
        os.environ["TELLER_DB_PASSWORD"] = "pw"  # pragma: allowlist secret
        with patch("teller.teller_db.resolve_profile", return_value=_LOCAL_PROFILE), \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.event.listens_for", return_value=lambda fn: fn):
            fake_create_engine.return_value = MagicMock(name="engine")
            first = teller_db.get_engine()
            second = teller_db.get_engine()
        self.assertIs(first, second)
        self.assertEqual(fake_create_engine.call_count, 1)

    # #R035: sslmode=require is forwarded into connect_args.
    def test_sslmode_require_forwarded(self):
        #R035-T01: Resolve a profile with `sslmode = "require"` and verify `create_engine` receives `sslmode=require` in `connect_args`.
        os.environ["TELLER_DB_PASSWORD"] = "pw"  # pragma: allowlist secret
        with patch("teller.teller_db.resolve_profile", return_value=_SUPABASE_PROFILE), \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.event.listens_for", return_value=lambda fn: fn):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
        connect_args = fake_create_engine.call_args.kwargs["connect_args"]
        self.assertEqual(connect_args["sslmode"], "require")
        self.assertEqual(connect_args["host"], "db.example.supabase.co")

    # #R035: sslmode=disable is omitted from connect_args.
    def test_sslmode_disable_omitted(self):
        #R035-T02: Resolve a profile with `sslmode = "disable"` and verify `connect_args` contains no `sslmode` key.
        os.environ["TELLER_DB_PASSWORD"] = "pw"  # pragma: allowlist secret
        with patch("teller.teller_db.resolve_profile", return_value=_LOCAL_PROFILE), \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.event.listens_for", return_value=lambda fn: fn):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
        connect_args = fake_create_engine.call_args.kwargs["connect_args"]
        self.assertNotIn("sslmode", connect_args)

    def test_sqlite_profile_uses_sqlite_engine_without_password_lookup(self):
        #R030-T02: Verify sqlite profile builds sqlite engine without password lookup.
        with patch("teller.teller_db.resolve_profile", return_value=_SQLITE_PROFILE), \
             patch("teller.teller_db._read_password") as fake_read_password, \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch.dict(os.environ, {"TELLER_DB_SQLCIPHER_KEY": "env-key"}, clear=False):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
        fake_read_password.assert_not_called()
        engine_url = fake_create_engine.call_args.args[0]
        self.assertEqual(engine_url, "sqlite://")
        self.assertIn("creator", fake_create_engine.call_args.kwargs)

    def test_resolve_sqlcipher_key_prefers_env_then_profile(self):
        #R030-T03: SQLCipher key resolver prefers env override and falls back to profile key.
        with patch.dict(os.environ, {"TELLER_DB_SQLCIPHER_KEY": "env-k"}, clear=False):
            self.assertEqual(teller_db._resolve_sqlcipher_key(_SQLITE_PROFILE), "env-k")
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(teller_db._resolve_sqlcipher_key(_SQLITE_PROFILE), "k")

    def test_resolve_sqlcipher_key_raises_when_missing(self):
        #R030-T04: SQLCipher key resolver raises when neither env nor profile provide a key.
        missing_key_profile = ResolvedProfile(
            name="sqlite",
            host="",
            port=0,
            dbname="",
            user="",
            onepsa_item="",
            search_path="teller",
            runtime_role="",
            sslmode="disable",
            target="sqlite",
            sqlite_path="/tmp/empty.sqlite3",
            sqlcipher_key="",
        )
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError):
                teller_db._resolve_sqlcipher_key(missing_key_profile)

    def test_sqlite_creator_creates_parent_dir_before_attach(self):
        #R045-T01: sqlite creator ensures the parent directory exists before ATTACH.
        sqlite_profile = ResolvedProfile(
            name="sqlite",
            host="",
            port=0,
            dbname="",
            user="",
            onepsa_item="",
            search_path="teller",
            runtime_role="",
            sslmode="disable",
            target="sqlite",
            sqlite_path=".database/test-sqlcipher.sqlite3",
            sqlcipher_key="k",
        )
        fake_cursor = MagicMock()
        fake_conn = MagicMock()
        fake_conn.cursor.return_value = fake_cursor
        fake_dbapi = MagicMock()
        fake_dbapi.connect.return_value = fake_conn
        fake_pysqlcipher = type("FakePysqlcipher3", (), {"dbapi2": fake_dbapi})()

        with patch("teller.teller_db.resolve_profile", return_value=sqlite_profile), \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.os.makedirs") as fake_makedirs, \
             patch.dict(sys.modules, {"pysqlcipher3": fake_pysqlcipher}):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
            creator = fake_create_engine.call_args.kwargs["creator"]
            creator()

        expected_sqlite_path = os.path.abspath(sqlite_profile.sqlite_path)
        fake_makedirs.assert_called_once_with(os.path.dirname(expected_sqlite_path), exist_ok=True)
        executed_sql = [call.args[0] for call in fake_cursor.execute.call_args_list]
        attach_sql = next(sql for sql in executed_sql if sql.startswith("ATTACH DATABASE "))
        self.assertIn(expected_sqlite_path.replace("'", "''"), attach_sql)

    def test_sqlcipher_adapter_handles_old_create_function_signature(self):
        #R045-T02: SQLCipher adapter retries create_function without deterministic kwarg.
        calls = []

        #R045: simulate old pysqlcipher create_function(name, num_params, func) API.
        def old_create_function(name, num_params, func):
            calls.append((name, num_params, func))
            return None

        raw_conn = MagicMock()
        raw_conn.create_function.side_effect = old_create_function
        adapter = teller_db._SqlcipherConnectionAdapter(raw_conn)

        adapter.create_function("regexp", 2, lambda *_args: True, deterministic=True)

        self.assertEqual(len(calls), 1)
        self.assertEqual(raw_conn.create_function.call_count, 2)
        self.assertEqual(raw_conn.create_function.call_args_list[0].kwargs, {"deterministic": True})
        self.assertEqual(raw_conn.create_function.call_args_list[1].kwargs, {})


class ConnectListenerTests(_IsolatedEnvTest):
    #R030: Capture SQLAlchemy connect-listener callback under test.
    def _capture_connect_listener(self, profile=None):
        os.environ["TELLER_DB_PASSWORD"] = "pw"  # pragma: allowlist secret
        captured = {}

        #R030: Stub SQLAlchemy event registration for listener capture.
        def fake_listens_for(target, _event_name):  # noqa: ARG001
            #R030: Register captured listener callable for assertions.
            def decorator(fn):
                captured["fn"] = fn
                return fn
            return decorator

        with patch("teller.teller_db.resolve_profile", return_value=profile or _LOCAL_PROFILE), \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.event.listens_for", side_effect=fake_listens_for):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
        return captured["fn"]

    # #R040: SET search_path and SET ROLE both execute when runtime_role is configured.
    def test_set_role_runs_when_configured(self):
        #R040-T01: Drive the connect listener with `runtime_role = "teller_write"` and verify both `SET search_path` and `SET ROLE` execute against the cursor.
        listener = self._capture_connect_listener()
        cursor = MagicMock()
        cursor.fetchone.side_effect = [('"teller","classy","matchy"',), ('"teller_write"',)]
        dbapi_conn = MagicMock()
        dbapi_conn.cursor.return_value = cursor
        listener(dbapi_conn, MagicMock())
        executed_sql = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertIn("SELECT string_agg(quote_ident(trim(schema_name)), ',')", executed_sql[0])
        self.assertIn('SET search_path TO "teller","classy","matchy"', executed_sql)
        self.assertIn("SELECT quote_ident(%s)", executed_sql)
        self.assertIn('SET ROLE "teller_write"', executed_sql)

    # #R040: SET ROLE is skipped when runtime_role is empty (e.g. Supabase profile).
    def test_set_role_skipped_when_empty(self):
        #R040-T02: Drive the connect listener with empty `runtime_role` and verify `SET ROLE` is not executed.
        listener = self._capture_connect_listener(profile=_SUPABASE_PROFILE)
        cursor = MagicMock()
        cursor.fetchone.return_value = ('"teller","classy","matchy"',)
        dbapi_conn = MagicMock()
        dbapi_conn.cursor.return_value = cursor
        listener(dbapi_conn, MagicMock())
        executed_sql = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertEqual(len(executed_sql), 2)
        self.assertIn("SELECT string_agg(quote_ident(trim(schema_name)), ',')", executed_sql[0])
        self.assertEqual(executed_sql[1], 'SET search_path TO "teller","classy","matchy"')
        self.assertFalse(any(sql.startswith("SET ROLE ") for sql in executed_sql))

    def test_empty_search_path_identifiers_raise_runtime_error(self):
        #R040-T03: connect listener rejects profiles whose search_path resolves to no identifiers.
        listener = self._capture_connect_listener(profile=_LOCAL_PROFILE)
        cursor = MagicMock()
        cursor.fetchone.return_value = (None,)
        dbapi_conn = MagicMock()
        dbapi_conn.cursor.return_value = cursor
        with self.assertRaises(RuntimeError):
            listener(dbapi_conn, MagicMock())


if __name__ == "__main__":
    unittest.main()
