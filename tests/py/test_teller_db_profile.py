import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

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
    "TELLER_DB_SQLITE_PATH",
    "TELLER_DB_SQLCIPHER_KEY",
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

_SQLITE_FIELDS = {
    "database": "/tmp/teller-test.sqlite3",
    "target": "sqlite",
    "sqlcipher_key": "sqlite-key",
}


#R001: Build deterministic onepsa field reader stub for profile tests.
def _make_onepsa_stub(fields):
    """Return a function that mimics _read_onepsa_fields for the given field dict."""

    #R001: Return selected onepsa fields for profile resolution fixtures.
    def stub(item, field_names):  # noqa: ARG001
        return {name: fields[name] for name in field_names if name in fields}

    return stub


class _IsolatedEnvTest(unittest.TestCase):
    #R001: Isolate environment and cwd for profile-resolution tests.
    def setUp(self):
        self._saved_env = {key: os.environ.pop(key) for key in _DB_ENV_KEYS if key in os.environ}
        self._tempdir = tempfile.TemporaryDirectory()
        self._cwd_before = Path.cwd()
        os.chdir(self._tempdir.name)
        from teller.teller_db_profile import reset_profile_cache
        reset_profile_cache()

    #R001: Restore environment and cleanup profile-resolution test state.
    def tearDown(self):
        os.chdir(self._cwd_before)
        self._tempdir.cleanup()
        for key in _DB_ENV_KEYS:
            os.environ.pop(key, None)
        for key, value in self._saved_env.items():
            os.environ[key] = value

    #R001: Write temporary db profile fixture file for tests.
    def _write_profile_file(self, payload, name="config/db-profiles.json"):
        path = Path(self._tempdir.name) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path


class ResolveProfileTests(_IsolatedEnvTest):
    # #R001: Missing profile files fail with setup guidance.
    def test_missing_profile_file_raises_with_copy_guidance(self):
        #R001-T01: Resolve with no profile file present and verify a `ProfileError` explains how to create `config/db-profiles.json` from `config/db-profiles-EXAMPLE.json`.
        with self.assertRaises(ProfileError) as ctx:
            resolve_profile()
        self.assertIn("cp config/db-profiles-EXAMPLE.json config/db-profiles.json", str(ctx.exception))

    # #R005: TELLER_DB_PROFILE_FILE wins over repo-local defaults.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SUPABASE_FIELDS))
    def test_explicit_profile_file_wins(self, _mock):
        #R005-T01: Point `TELLER_DB_PROFILE_FILE` at a temp file and verify it is loaded ahead of repo defaults.
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
        #R005-T02: With no file at any candidate path, verify resolution fails fast with profile-setup guidance.
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
        #R010-T01: Load a profile missing `host` and verify a `ProfileError` is raised.
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

    @patch("teller.teller_db_profile._read_onepsa_fields")
    def test_invalid_sslmode_from_profile_fields_raises_profile_error(self, mock_read):
        #R010-T03: Verify invalid sslmode from profile fields raises ProfileError.
        fields = dict(_SUPABASE_FIELDS, sslmode="bogus")
        mock_read.side_effect = _make_onepsa_stub(fields)
        self._write_profile_file(
            {
                "default_profile": "remote",
                "profiles": {"remote": {"1psa_item": "eggnest_supabase"}},
            }
        )
        with self.assertRaises(ProfileError) as ctx:
            resolve_profile()
        self.assertIn("DB profile sslmode must be one of", str(ctx.exception))

    # #R015: TELLER_DB_PROFILE overrides default_profile.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SUPABASE_FIELDS))
    def test_env_profile_name_overrides_default(self, _mock):
        #R015-T01: With `TELLER_DB_PROFILE=supabase` and a file whose `default_profile` is `local`, verify the supabase profile is resolved.
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
        #R020-T01: Resolve with the local profile and `TELLER_DB_HOST=remote.example` set; verify host is overridden but other fields come from the profile.
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_HOST"] = "remote.example"
        profile = resolve_profile()
        self.assertEqual(profile.host, "remote.example")
        self.assertEqual(profile.dbname, "prod")
        self.assertEqual(profile.user, "teller")

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_profile_resolution_refreshes_when_env_changes_without_manual_cache_clear(self, _mock):
        #R020-T04: Verify env changes refresh resolved profile without manual cache reset.
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_HOST"] = "first-host"
        first = resolve_profile()

        os.environ["TELLER_DB_HOST"] = "second-host"
        second = resolve_profile()

        self.assertEqual(first.host, "first-host")
        self.assertEqual(second.host, "second-host")

    # #R020: TELLER_PSA_ITEM no longer overrides onepsa_item (item comes from JSON only).
    # Instead we verify TELLER_DB_USER can override the user field.
    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_env_user_override(self, _mock):
        #R020-T02: Resolve with `TELLER_DB_USER=custom_user` set; verify only the runtime user field is overridden.
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_USER"] = "custom_user"
        profile = resolve_profile()
        self.assertEqual(profile.user, "custom_user")

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_invalid_port_override_raises_profile_error(self, _mock):
        #R020-T05: Verify invalid env port override raises ProfileError.
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
        #R010-T02: Load a profile with `sslmode = "bogus"` and verify a `ProfileError` is raised.
        self._write_profile_file({
            "default_profile": "local",
            "profiles": {"local": {"1psa_item": "localhost_postgres_teller"}},
        })
        os.environ["TELLER_DB_SSLMODE"] = "bogus"
        with self.assertRaises(ProfileError) as ctx:
            resolve_profile()
        self.assertIn("TELLER_DB_SSLMODE must be one of", str(ctx.exception))

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SQLITE_FIELDS))
    def test_sqlite_profile_resolves_sqlite_target_and_path(self, _mock):
        #R001-T02: Verify sqlite profile resolves sqlite target and sqlite_path fields.
        self._write_profile_file(
            {
                "default_profile": "sqlite_local",
                "profiles": {"sqlite_local": {"1psa_item": "sqlite_local_item"}},
            }
        )
        profile = resolve_profile()
        self.assertEqual(profile.target, "sqlite")
        self.assertEqual(profile.sqlite_path, "/tmp/teller-test.sqlite3")
        self.assertEqual(profile.sqlcipher_key, "sqlite-key")

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_LOCAL_FIELDS))
    def test_profile_named_sqlite_forces_sqlite_target_when_source_target_is_local(self, _mock):
        #R021-T01: Resolve with `default_profile=sqlite` while source fields report `target=local`; verify `target=sqlite` with default sqlite file path semantics.
        self._write_profile_file(
            {
                "default_profile": "sqlite",
                "profiles": {"sqlite": {"1psa_item": "sqlite_item"}},
            }
        )
        profile = resolve_profile()
        self.assertEqual(profile.name, "sqlite")
        self.assertEqual(profile.target, "sqlite")
        self.assertEqual(profile.sslmode, "disable")
        self.assertTrue(profile.sqlite_path.endswith(".database/teller.sqlite3"))

    @patch("teller.teller_db_profile._read_onepsa_fields", side_effect=_make_onepsa_stub(_SQLITE_FIELDS))
    def test_sqlcipher_key_env_override(self, _mock):
        #R020-T03: Verify sqlcipher key env override wins over profile value.
        self._write_profile_file(
            {
                "default_profile": "sqlite_local",
                "profiles": {"sqlite_local": {"1psa_item": "sqlite_local_item"}},
            }
        )
        os.environ["TELLER_DB_SQLCIPHER_KEY"] = "env-key"
        profile = resolve_profile()
        self.assertEqual(profile.target, "sqlite")
        self.assertEqual(profile.sqlcipher_key, "env-key")


class HelperBranchCoverageTests(_IsolatedEnvTest):
    def test_read_onepsa_fields_returns_empty_when_library_missing(self):
        #R010-T04: _read_onepsa_fields returns {} when libonepsa cannot be loaded.
        from teller import teller_db_profile as profile_mod

        with patch.object(profile_mod.ctypes, "CDLL", side_effect=OSError("missing")):
            self.assertEqual(profile_mod._read_onepsa_fields("item", ("host", "port")), {})

    def test_read_onepsa_fields_stops_after_first_error(self):
        #R010-T05: libonepsa field errors stop further field reads.
        from teller import teller_db_profile as profile_mod

        fake_lib = MagicMock()
        fake_lib.calls = 0

        def _onepsa_get_field(item, field, err_ptr):  # noqa: ARG001
            fake_lib.calls += 1
            err_ptr._obj.value = b"lookup failed"
            return None

        fake_lib.OnepsaGetField = MagicMock(side_effect=_onepsa_get_field)
        fake_lib.OnepsaStringFree = MagicMock(return_value=None)
        with patch.object(profile_mod.ctypes, "CDLL", return_value=fake_lib):
            parsed = profile_mod._read_onepsa_fields("item", ("host", "port", "database"))
        self.assertEqual(parsed, {})
        self.assertEqual(fake_lib.calls, 1)

    def test_read_env_file_fields_parses_only_item_prefixed_lines(self):
        #R010-T06: ~/.env fallback parser reads only ITEM.field=value entries.
        from teller import teller_db_profile as profile_mod

        with tempfile.TemporaryDirectory() as home_dir:
            env_path = Path(home_dir) / ".env"
            env_path.write_text(
                "\n".join(
                    [
                        "item.host=localhost",
                        "item.port=5432",
                        "other.host=ignore",
                        "item.bad_line",
                    ]
                ),
                encoding="utf-8",
            )
            with patch.object(profile_mod.Path, "home", return_value=Path(home_dir)):
                fields = profile_mod._read_env_file_fields("item")
        self.assertEqual(fields["host"], "localhost")
        self.assertEqual(fields["port"], "5432")
        self.assertNotIn("bad_line", fields)

    def test_fetch_record_from_onepsa_falls_back_to_env_when_host_missing(self):
        #R010-T07: onepsa host-missing records fall back to ~/.env-derived fields.
        from teller import teller_db_profile as profile_mod

        with (
            patch.object(profile_mod, "_read_onepsa_fields", return_value={"database": "prod"}),
            patch.object(
                profile_mod,
                "_read_env_file_fields",
                return_value={
                    "host": "fallback.example",
                    "port": "5432",
                    "database": "prod",
                    "username": "teller",
                    "schema": "teller",
                    "runtime_role": "teller_write",
                    "target": "local",
                },
            ),
        ):
            record = profile_mod._fetch_record_from_onepsa("item")
        self.assertEqual(record["host"], "fallback.example")
        self.assertEqual(record["target"], "local")

    def test_load_profile_document_reports_invalid_shapes(self):
        #R010-T08: invalid JSON/non-dict/empty-profiles documents fail with ProfileError.
        from teller import teller_db_profile as profile_mod

        bad_json = self._write_profile_file("{}", name="config/db-profiles.local.json")
        bad_json.write_text("{", encoding="utf-8")
        with self.assertRaises(ProfileError):
            profile_mod._load_profile_document()

        bad_json.write_text("[]", encoding="utf-8")
        with self.assertRaises(ProfileError):
            profile_mod._load_profile_document()

        bad_json.write_text(json.dumps({"default_profile": "x", "profiles": {}}), encoding="utf-8")
        with self.assertRaises(ProfileError):
            profile_mod._load_profile_document()

    def test_select_profile_name_requires_default_when_no_override(self):
        #R015-T02: selection fails when override/default_profile are both missing.
        from teller import teller_db_profile as profile_mod

        with self.assertRaises(ProfileError):
            profile_mod._select_profile_name({"profiles": {"x": {"1psa_item": "item"}}})

    def test_resolve_onepsa_item_reports_available_profiles(self):
        #R010-T09: missing profile name error includes available profile names.
        from teller import teller_db_profile as profile_mod

        doc = {"profiles": {"a": {"1psa_item": "item_a"}, "b": {"1psa_item": "item_b"}}}
        with self.assertRaises(ProfileError) as ctx:
            profile_mod._resolve_onepsa_item(doc, "missing")
        self.assertIn("available profiles", str(ctx.exception))
        self.assertIn("a", str(ctx.exception))
        self.assertIn("b", str(ctx.exception))

    def test_apply_env_overrides_sqlite_path_forces_sqlite_semantics(self):
        #R020-T06: sqlite-path env override forces sqlite target and clears postgres fields.
        from teller import teller_db_profile as profile_mod

        record = {
            "host": "localhost",
            "port": 5432,
            "dbname": "prod",
            "user": "teller",
            "runtime_role": "teller_write",
            "search_path": "teller",
            "target": "local",
            "sslmode": "disable",
            "sqlite_path": "",
            "sqlcipher_key": "",
        }
        with patch.dict(
            os.environ,
            {"TELLER_DB_SQLITE_PATH": "/tmp/x.sqlite3", "TELLER_DB_SQLCIPHER_KEY": "abc"},
            clear=False,
        ):
            overridden = profile_mod._apply_env_overrides(record)
        self.assertEqual(overridden["target"], "sqlite")
        self.assertEqual(overridden["host"], "")
        self.assertEqual(overridden["port"], 0)
        self.assertEqual(overridden["sslmode"], "disable")
        self.assertEqual(overridden["sqlite_path"], "/tmp/x.sqlite3")
        self.assertEqual(overridden["sqlcipher_key"], "abc")

if __name__ == "__main__":
    unittest.main()
