from hypothesis import given, settings, strategies as st

from teller.teller_db_profile import _build_record


@given(
    host=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    port_raw=st.one_of(st.none(), st.text(min_size=0, max_size=8)),
    database=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    username=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    schema=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    runtime_role=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    target=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    sslmode=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
)
@settings(max_examples=80, deadline=None, derandomize=True)
def test_build_record_always_returns_expected_shape(
    host, port_raw, database, username, schema, runtime_role, target, sslmode
):
    result = _build_record(host, port_raw, database, username, schema, runtime_role, target, sslmode)
    assert set(result.keys()) == {
        "host",
        "port",
        "dbname",
        "user",
        "search_path",
        "runtime_role",
        "target",
        "sslmode",
    }
    assert isinstance(result["port"], int)
    assert result["target"] in {"local", "managed"}
    assert result["sslmode"] in {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}


@given(st.one_of(st.none(), st.text(min_size=0, max_size=8)))
@settings(max_examples=40, deadline=None, derandomize=True)
def test_build_record_invalid_port_falls_back_to_default(port_raw):
    result = _build_record("localhost", port_raw, "prod", "teller", "teller", "", "local", "disable")
    if port_raw and port_raw.isdigit():
        assert result["port"] == int(port_raw)
    else:
        assert result["port"] == 5432
from hypothesis import given, settings, strategies as st



@given(
    host=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    port_raw=st.one_of(st.none(), st.text(min_size=0, max_size=8)),
    database=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    username=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    schema=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    runtime_role=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    target=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    sslmode=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
)
@settings(max_examples=80, deadline=None, derandomize=True)
def test_build_record_always_returns_expected_shape(
    host, port_raw, database, username, schema, runtime_role, target, sslmode
):
    result = _build_record(host, port_raw, database, username, schema, runtime_role, target, sslmode)
    assert set(result.keys()) == {
        "host",
        "port",
        "dbname",
        "user",
        "search_path",
        "runtime_role",
        "target",
        "sslmode",
    }
    assert isinstance(result["port"], int)
    assert result["target"] in {"local", "managed"}
    assert result["sslmode"] in {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}


@given(st.one_of(st.none(), st.text(min_size=0, max_size=8)))
@settings(max_examples=40, deadline=None, derandomize=True)
def test_build_record_invalid_port_falls_back_to_default(port_raw):
    result = _build_record("localhost", port_raw, "prod", "teller", "teller", "", "local", "disable")
    if port_raw and port_raw.isdigit():
        assert result["port"] == int(port_raw)
    else:
        assert result["port"] == 5432
