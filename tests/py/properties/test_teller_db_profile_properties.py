from hypothesis import given, settings, strategies as st

from teller.teller_db_profile import ProfileError, _build_record

_VALID_SSLMODES = ("disable", "allow", "prefer", "require", "verify-ca", "verify-full")


@given(
    host=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    port_raw=st.one_of(st.none(), st.text(min_size=0, max_size=8)),
    database=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    username=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    schema=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    runtime_role=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    target=st.one_of(st.none(), st.text(min_size=0, max_size=24)),
    sslmode=st.one_of(st.none(), st.sampled_from(_VALID_SSLMODES)),
)
@settings(max_examples=500, deadline=None, derandomize=True)
def test_build_record_always_returns_expected_shape(
    #R001: Cover traceability for this helper/test behavior.
    host, port_raw, database, username, schema, runtime_role, target, sslmode
):
    result = _build_record(host, port_raw, database, username, None, schema, runtime_role, target, sslmode)
    assert set(result.keys()) == {
        "host",
        "port",
        "dbname",
        "user",
        "search_path",
        "runtime_role",
        "target",
        "sslmode",
        "sqlite_path",
        "sqlcipher_key",
    }
    assert isinstance(result["port"], int)
    assert result["target"] in {"local", "managed", "sqlite"}
    assert result["sslmode"] in {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}


@given(st.one_of(st.none(), st.text(min_size=0, max_size=8)))
@settings(max_examples=500, deadline=None, derandomize=True)
def test_build_record_invalid_port_falls_back_to_default(port_raw):
    #R001: Cover traceability for this helper/test behavior.
    result = _build_record("localhost", port_raw, "prod", "teller", None, "teller", "", "local", "disable")
    try:
        expected_port = int(port_raw) if port_raw is not None else 5432
    except (TypeError, ValueError):
        expected_port = 5432
    assert result["port"] == expected_port


@given(
    st.text(min_size=1, max_size=24).filter(
        lambda value: value.strip() and value.strip().lower() not in set(_VALID_SSLMODES)
    )
)
@settings(max_examples=500, deadline=None, derandomize=True)
def test_build_record_invalid_sslmode_raises_profile_error(sslmode):
    #R001: Cover traceability for this helper/test behavior.
    try:
        _build_record("localhost", "5432", "prod", "teller", None, "teller", "", "local", sslmode)
    except ProfileError:
        return
    raise AssertionError(f"Expected ProfileError for invalid sslmode {sslmode!r}")
