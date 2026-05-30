import os
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
    "TELLER_PSA_ITEM",
)

_LOCAL_PROFILE = ResolvedProfile(
    name="local", host="localhost", port=5432, dbname="prod", user="teller",
    onepsa_item="localhost_postgres_teller", search_path="teller",
    runtime_role="teller_write", sslmode="disable", target="local", sqlite_path="",
)

_SUPABASE_PROFILE = ResolvedProfile(
    name="supabase", host="db.example.supabase.co", port=5432, dbname="postgres",
    user="postgres", onepsa_item="eggnest_supabase", search_path="teller",
    runtime_role="", sslmode="require", target="managed", sqlite_path="",
)

_SQLITE_PROFILE = ResolvedProfile(
    name="sqlite", host="", port=0, dbname="", user="",
    onepsa_item="", search_path="teller", runtime_role="",
    sslmode="disable", target="sqlite", sqlite_path="/tmp/teller-test.sqlite3",
)


class _IsolatedEnvTest(unittest.TestCase):
    def setUp(self):
        self._saved_env = {key: os.environ.pop(key) for key in _DB_ENV_KEYS if key in os.environ}
        teller_db._engine = None

    def tearDown(self):
        for key in _DB_ENV_KEYS:
            os.environ.pop(key, None)
        for key, value in self._saved_env.items():
            os.environ[key] = value
        teller_db._engine = None


class PasswordResolutionTests(_IsolatedEnvTest):
    # #R025: TELLER_DB_PASSWORD short-circuits libonepsa.
    def test_env_password_wins(self):
        #R025-T01
        os.environ["TELLER_DB_PASSWORD"] = "from-env"  # pragma: allowlist secret
        with patch("teller.teller_db._read_password_from_onepsa") as fake_onepsa:
            fake_onepsa.side_effect = AssertionError("libonepsa must not be called")
            self.assertEqual(teller_db._read_password(_LOCAL_PROFILE), "from-env")
            fake_onepsa.assert_not_called()

    # #R025: Empty onepsa_item with no env password raises a clear error.
    def test_missing_onepsa_item_raises(self):
        #R025-T02
        empty_profile = ResolvedProfile(
            name="noitem", host="h", port=5432, dbname="d", user="u",
            onepsa_item="", search_path="teller", runtime_role="",
            sslmode="disable", target="local", sqlite_path="",
        )
        with self.assertRaises(RuntimeError):
            teller_db._read_password(empty_profile)


class EngineConstructionTests(_IsolatedEnvTest):
    # #R030: Engine is built once and cached.
    def test_engine_is_cached(self):
        #R030-T01
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
        #R035-T01
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
        #R035-T02
        os.environ["TELLER_DB_PASSWORD"] = "pw"  # pragma: allowlist secret
        with patch("teller.teller_db.resolve_profile", return_value=_LOCAL_PROFILE), \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.event.listens_for", return_value=lambda fn: fn):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
        connect_args = fake_create_engine.call_args.kwargs["connect_args"]
        self.assertNotIn("sslmode", connect_args)

    def test_sqlite_profile_uses_sqlite_engine_without_password_lookup(self):
        with patch("teller.teller_db.resolve_profile", return_value=_SQLITE_PROFILE), \
             patch("teller.teller_db._read_password") as fake_read_password, \
             patch("teller.teller_db.create_engine") as fake_create_engine, \
             patch("teller.teller_db.event.listens_for", return_value=lambda fn: fn):
            fake_create_engine.return_value = MagicMock(name="engine")
            teller_db.get_engine()
        fake_read_password.assert_not_called()
        engine_url = fake_create_engine.call_args.args[0]
        self.assertEqual(engine_url, "sqlite:////tmp/teller-test.sqlite3")


class ConnectListenerTests(_IsolatedEnvTest):
    def _capture_connect_listener(self, profile=None):
        os.environ["TELLER_DB_PASSWORD"] = "pw"  # pragma: allowlist secret
        captured = {}

        def fake_listens_for(target, _event_name):  # noqa: ARG001
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
        #R040-T01
        listener = self._capture_connect_listener()
        cursor = MagicMock()
        cursor.fetchone.side_effect = [('"teller"',), ('"teller_write"',)]
        dbapi_conn = MagicMock()
        dbapi_conn.cursor.return_value = cursor
        listener(dbapi_conn, MagicMock())
        executed_sql = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertIn("SELECT string_agg(quote_ident(trim(schema_name)), ',')", executed_sql[0])
        self.assertIn('SET search_path TO "teller"', executed_sql)
        self.assertIn("SELECT quote_ident(%s)", executed_sql)
        self.assertIn('SET ROLE "teller_write"', executed_sql)

    # #R040: SET ROLE is skipped when runtime_role is empty (e.g. Supabase profile).
    def test_set_role_skipped_when_empty(self):
        #R040-T02
        listener = self._capture_connect_listener(profile=_SUPABASE_PROFILE)
        cursor = MagicMock()
        cursor.fetchone.return_value = ('"teller"',)
        dbapi_conn = MagicMock()
        dbapi_conn.cursor.return_value = cursor
        listener(dbapi_conn, MagicMock())
        executed_sql = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertEqual(len(executed_sql), 2)
        self.assertIn("SELECT string_agg(quote_ident(trim(schema_name)), ',')", executed_sql[0])
        self.assertEqual(executed_sql[1], 'SET search_path TO "teller"')
        self.assertFalse(any(sql.startswith("SET ROLE ") for sql in executed_sql))


if __name__ == "__main__":
    unittest.main()
