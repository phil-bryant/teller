from __future__ import annotations

import os
import string
from contextlib import contextmanager

import pytest
from hypothesis import given, strategies as st

from teller.teller_db_profile import ProfileError, _apply_env_overrides, _build_record

_SAFE_ENV_TEXT = st.text(alphabet=st.characters(min_codepoint=33, max_codepoint=126), min_size=1, max_size=20)
_SAFE_ENV_TEXT_OPTIONAL = st.text(alphabet=st.characters(min_codepoint=32, max_codepoint=126), min_size=0, max_size=20)


@contextmanager
def _override_env(temp_values: dict[str, str]):
    original = os.environ.copy()
    try:
        for key in (
            "TELLER_DB_HOST",
            "TELLER_DB_PORT",
            "TELLER_DB_NAME",
            "TELLER_DB_USER",
            "TELLER_DB_ROLE",
            "TELLER_DB_SSLMODE",
            "TELLER_DB_SEARCH_PATH",
        ):
            os.environ.pop(key, None)
        os.environ.update(temp_values)
        yield
    finally:
        os.environ.clear()
        os.environ.update(original)


@given(
    host=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    port_raw=st.one_of(st.none(), st.text(min_size=0, max_size=8)),
    database=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    username=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    schema=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    runtime_role=st.one_of(st.none(), st.text(min_size=0, max_size=30)),
    target=st.one_of(st.none(), st.text(min_size=0, max_size=12)),
    sslmode=st.one_of(st.none(), st.text(min_size=0, max_size=20)),
)
def test_build_record_normalizes_shape_and_allowed_enums(
    host,
    port_raw,
    database,
    username,
    schema,
    runtime_role,
    target,
    sslmode,
):
    record = _build_record(host, port_raw, database, username, schema, runtime_role, target, sslmode)
    assert set(record.keys()) == {
        "host",
        "port",
        "dbname",
        "user",
        "search_path",
        "runtime_role",
        "target",
        "sslmode",
    }
    assert isinstance(record["port"], int)
    assert record["target"] in {"local", "managed"}
    assert record["sslmode"] in {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}


@given(
    host=_SAFE_ENV_TEXT,
    db_name=_SAFE_ENV_TEXT,
    user=_SAFE_ENV_TEXT,
    role=_SAFE_ENV_TEXT_OPTIONAL,
    search_path=_SAFE_ENV_TEXT,
    sslmode=st.sampled_from(["disable", "allow", "prefer", "require", "verify-ca", "verify-full"]),
    port=st.integers(min_value=1, max_value=65535),
)
def test_apply_env_overrides_updates_only_expected_fields(host, db_name, user, role, search_path, sslmode, port):
    base = _build_record("localhost", "5432", "prod", "teller", "teller", "", "local", "disable")
    with _override_env(
        {
            "TELLER_DB_HOST": host,
            "TELLER_DB_NAME": db_name,
            "TELLER_DB_USER": user,
            "TELLER_DB_ROLE": role,
            "TELLER_DB_SEARCH_PATH": search_path,
            "TELLER_DB_SSLMODE": sslmode,
            "TELLER_DB_PORT": str(port),
        }
    ):
        overridden = _apply_env_overrides(base)

    assert overridden["host"] == host
    assert overridden["dbname"] == db_name
    assert overridden["user"] == user
    assert overridden["runtime_role"] == role.strip()
    assert overridden["search_path"] == search_path
    assert overridden["sslmode"] == sslmode
    assert overridden["port"] == port
    assert overridden["target"] == base["target"]


@given(st.text(alphabet=string.printable, min_size=1, max_size=8).filter(lambda value: not value.isdigit()))
def test_apply_env_overrides_port_parsing_matches_int_semantics(port_value):
    base = _build_record("localhost", "5432", "prod", "teller", "teller", "", "local", "disable")
    with _override_env({"TELLER_DB_PORT": port_value}):
        try:
            expected = int(port_value)
        except ValueError:
            with pytest.raises(ProfileError):
                _apply_env_overrides(base)
        else:
            overridden = _apply_env_overrides(base)
            assert overridden["port"] == expected


@given(st.text(alphabet=string.printable, min_size=1, max_size=20))
def test_apply_env_overrides_rejects_unknown_sslmode_values(sslmode):
    allowed = {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
    if sslmode in allowed:
        return
    base = _build_record("localhost", "5432", "prod", "teller", "teller", "", "local", "disable")
    with _override_env({"TELLER_DB_SSLMODE": sslmode}):
        with pytest.raises(ProfileError):
            _apply_env_overrides(base)
