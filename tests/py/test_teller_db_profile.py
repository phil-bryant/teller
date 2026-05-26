import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from teller.teller_db_profile import ProfileError, resolve_profile


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
    "TELLER_PSA_ITEM",
)

_LOCAL_FIELDS = {
    "host": "localhost",
    "port": "5432",
    "database": "prod",
    "username": "teller",
    "schema": "teller",
    "runtime_role": "teller_write",
    "target": "local",
}

_SUPABASE_FIELDS = {
    "host": "db.example.supabase.co",
    "port": "5432",
    "database": "postgres",
    "username": "postgres",
    "schema": "teller",
    "runtime_role": "",
    "target": "managed",
}


def _make_onepsa_stub(fields):
    """Return a function that mimics _read_onepsa_fields for the given field dict."""

    def stub(item, field_names):  # noqa: ARG001
        return {name: fields[name] for name in field_names if name in fields}

    return stub


class _IsolatedEnvTest(unittest.TestCase):
    def setUp(self):
        self._saved_env = {key: os.environ.pop(key) for key in _DB_ENV_KEYS if key in os.environ}
        self._tempdir = tempfile.TemporaryDirectory()
        self._cwd_before = Path.cwd()
        os.chdir(self._tempdir.name)
        from teller.teller_db_profile import reset_profile_cache
        reset_profile_cache()

    def tearDown(self):
        os.chdir(self._cwd_before)
        self._tempdir.cleanup()
        for key in _DB_ENV_KEYS:
            os.environ.pop(key, None)
        for key, value in self._saved_env.items():
            os.environ[key] = value

    def _write_profile_file(self, payload, name="config/db-profiles.json"):
        path = Path(self._tempdir.name) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path


class ResolveProfileTests(_IsolatedEnvTest):
    # #R001: Missing profile files fail with setup guidance.
    def test_missing_profile_file_raises_with_copy_guidance(self):
        #R001-T01
        with self.assertRaises(ProfileError) as ctx:
            resolve_profile()
        self.assertIn("cp config/db-profiles-EXAMPLE.json config/db-profiles.json", str(ctx.exception))

    # #R005: TELLER_DB_PROFILE_FILE wins over repo-local defaults.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SUPABASE_FIELDS))
    def test_explicit_profile_file_wins(self, _mock):
        #R005-T01
        explicit = self._write_profile_file({
            "default_profile": "remote",
            "profiles": {"remote": {"1psa_item": "my_remote_item"}},
        }, name="explicit.json")
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_PROFILE_FILE"] = str(explicit)
        profile = resolve_profile()
        self.assertEqual(profile.name, "remote")
        self.assertEqual(profile.onepsa_item, "my_remote_item")
        self.assertEqual(profile.host, "db.example.supabase.co")

    # #R005: Missing profile files must not silently fall back.
    def test_no_file_anywhere_raises(self):
        #R005-T02
        with self.assertRaises(ProfileError):
            resolve_profile()

    # #R005: config profiles are preferred and used for local repository resolution.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SUPABASE_FIELDS))
    def test_config_profile_used_for_resolution(self, _mock):
        config_dir = Path(self._tempdir.name) / "config"
        config_dir.mkdir(parents=True, exist_ok=True)
        (config_dir / "db-profiles.local.json").write_text(
            json.dumps(
                {
                    "default_profile": "remote-local",
                    "profiles": {"remote-local": {"1psa_item": "local_config_item"}},
                }
            ),
            encoding="utf-8",
        )
        profile = resolve_profile()
        self.assertEqual(profile.name, "remote-local")
        self.assertEqual(profile.onepsa_item, "local_config_item")

    # #R010: Missing 1psa_item field raises ProfileError.
    def test_missing_onepsa_item_rejected(self):
        #R010-T01
        self._write_profile_file({
            "default_profile": "broken",
            "profiles": {"broken": {}},
        })
        with self.assertRaises(ProfileError):
            resolve_profile()

    # #R010: Invalid target from 1psa defaults to local.
    @patch("teller.teller_db_profile._read_onepsa_fields")
    def test_invalid_target_defaults_to_local(self, mock_read):
        fields = dict(_LOCAL_FIELDS, target="bogus")
        mock_read.side_effect = _make_onepsa_stub(fields)
        self._write_profile_file({
            "default_profile": "x",
            "profiles": {"x": {"1psa_item": "item_x"}},
        })
        profile = resolve_profile()
        self.assertEqual(profile.target, "local")

    # #R015: TELLER_DB_PROFILE overrides default_profile.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SUPABASE_FIELDS))
    def test_env_profile_name_overrides_default(self, _mock):
        #R015-T01
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {
                "local": {"1psa_item": "localhost_postgres_teller"},
                "supabase": {"1psa_item": "eggnest_supabase"},
            },
        })
        os.environ["TELLER_DB_PROFILE"] = "supabase"
        profile = resolve_profile()
        self.assertEqual(profile.name, "supabase")
        self.assertEqual(profile.onepsa_item, "eggnest_supabase")
        self.assertEqual(profile.sslmode, "require")

    # #R020: TELLER_DB_HOST overrides the 1psa-sourced host without disturbing other fields.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_env_host_override_keeps_other_fields(self, _mock):
        #R020-T01
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_HOST"] = "remote.example"
        profile = resolve_profile()
        self.assertEqual(profile.host, "remote.example")
        self.assertEqual(profile.dbname, "prod")
        self.assertEqual(profile.user, "teller")

    # #R020: TELLER_PSA_ITEM no longer overrides onepsa_item (item comes from JSON only).
    # Instead we verify TELLER_DB_USER can override the user field.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_env_user_override(self, _mock):
        #R020-T02
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_USER"] = "custom_user"
        profile = resolve_profile()
        self.assertEqual(profile.user, "custom_user")

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_invalid_port_override_raises_profile_error(self, _mock):
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_PORT"] = "not-a-number"
        with self.assertRaises(ProfileError) as ctx:
            resolve_profile()
        self.assertIn("TELLER_DB_PORT must be an integer", str(ctx.exception))

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_invalid_sslmode_override_raises_profile_error(self, _mock):
        #R010-T02
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_SSLMODE"] = "bogus"
        with self.assertRaises(ProfileError) as ctx:
            resolve_profile()
        self.assertIn("TELLER_DB_SSLMODE must be one of", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
