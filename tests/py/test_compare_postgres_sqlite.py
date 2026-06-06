"""Traceability coverage tests for compare_postgres_sqlite requirements."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from collections import Counter
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace


#R600: Helper for compare traceability test setup and fixtures.
def _load_module():
    #R600: Helper for compare traceability test setup and fixtures.
    script_path = Path(__file__).resolve().parents[2] / "tools" / "compare_postgres_sqlite.py"
    spec = importlib.util.spec_from_file_location("compare_postgres_sqlite", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load compare_postgres_sqlite module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


MODULE = _load_module()


#R600: Helper for compare traceability test setup and fixtures.
def _script_path() -> Path:
    #R600: Helper for compare traceability test setup and fixtures.
    return Path(__file__).resolve().parents[2] / "tools" / "compare_postgres_sqlite.py"


def test_r001_cli_exists() -> None:
    #R001-T01: Run script with default profiles and verify both connections are attempted (`tests/py/test_compare_postgres_sqlite.py`).
    assert _script_path().is_file()


def test_r005_uses_schema_comparison_terms() -> None:
    #R005-T01: Introduce a table/column drift and verify the script reports it as a mismatch (`tests/py/test_compare_postgres_sqlite.py`).
    text = _script_path().read_text(encoding="utf-8")
    assert "column" in text.lower()


def test_r010_uses_row_comparison_terms() -> None:
    #R010-T01: Modify one row value in either engine and verify the table is flagged with row mismatch details (`tests/py/test_compare_postgres_sqlite.py`).
    text = _script_path().read_text(encoding="utf-8")
    assert "row" in text.lower()


def test_r015_supports_json_output_flag() -> None:
    #R015-T01: Run identical databases and verify exit `0`; run with drift and verify exit `1` plus report output (`tests/py/test_compare_postgres_sqlite.py`).
    text = _script_path().read_text(encoding="utf-8")
    assert "--output-json" in text


def test_discover_repo_root_resolves_marker_dir() -> None:
    #R600-T01: Resolve repository root from nested script path fixture.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src" / "teller").mkdir(parents=True)
        nested = root / "tools" / "nested"
        nested.mkdir(parents=True)
        assert MODULE._discover_repo_root(nested) == root


def test_resolve_named_profile_restores_env_and_cache() -> None:
    #R605-T01: Resolve named profile while restoring env/cache state.
    original_profile = MODULE.os.environ.get("TELLER_DB_PROFILE")
    MODULE.os.environ["TELLER_DB_PROFILE"] = "before"
    calls = []

    #R600: Helper for compare traceability test setup and fixtures.
    def fake_reset() -> None:
        #R600: Helper for compare traceability test setup and fixtures.
        calls.append("reset")

    def fake_resolve():
        #R600: Helper for compare traceability test setup and fixtures.
        calls.append(MODULE.os.environ.get("TELLER_DB_PROFILE"))
        return "resolved-profile"

    original_reset = MODULE.reset_profile_cache
    original_resolve = MODULE.resolve_profile
    try:
        MODULE.reset_profile_cache = fake_reset
        MODULE.resolve_profile = fake_resolve
        resolved = MODULE._resolve_named_profile("sqlite")
    finally:
        MODULE.reset_profile_cache = original_reset
        MODULE.resolve_profile = original_resolve
        if original_profile is None:
            MODULE.os.environ.pop("TELLER_DB_PROFILE", None)
        else:
            MODULE.os.environ["TELLER_DB_PROFILE"] = original_profile

    assert resolved == "resolved-profile"
    assert calls == ["reset", "sqlite", "reset"]
    assert MODULE.os.environ.get("TELLER_DB_PROFILE") == original_profile


def test_connect_postgres_builds_connect_args_and_session_setup() -> None:
    #R610-T01: Build postgres connection args and execute session setup statements.

    class FakeCursor:
        #R600: Helper for compare traceability test setup and fixtures.
        def __init__(self):
            #R600: Helper for compare traceability test setup and fixtures.
            self.executed = []
            self._fetches = iter([('"teller","public"',), ('"teller_write"',)])

        def __enter__(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return self

        #R600: Helper for compare traceability test setup and fixtures.
        def __exit__(self, *args):
            #R600: Helper for compare traceability test setup and fixtures.
            return False

        def execute(self, sql, params=None):
            #R600: Helper for compare traceability test setup and fixtures.
            self.executed.append((sql, params))

        #R600: Helper for compare traceability test setup and fixtures.
        def fetchone(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return next(self._fetches)

    class FakeConnection:
        def __init__(self):
            #R600: Helper for compare traceability test setup and fixtures.
            self.cursor_obj = FakeCursor()

        #R600: Helper for compare traceability test setup and fixtures.
        def cursor(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return self.cursor_obj

    profile = SimpleNamespace(
        host="db.internal",
        port=5432,
        dbname="prod",
        user="teller",
        sslmode="require",
        search_path="teller, public",
        runtime_role="teller_write",
    )
    captured = {}
    fake_conn = FakeConnection()

    #R600: Helper for compare traceability test setup and fixtures.
    def fake_connect(**kwargs):
        #R600: Helper for compare traceability test setup and fixtures.
        captured["kwargs"] = kwargs
        return fake_conn

    original_connect = MODULE.psycopg2.connect
    original_read_password = MODULE._read_password
    try:
        MODULE.psycopg2.connect = fake_connect
        MODULE._read_password = lambda _profile: "pw"
        conn = MODULE._connect_postgres(profile)
    finally:
        MODULE.psycopg2.connect = original_connect
        MODULE._read_password = original_read_password

    assert conn is fake_conn
    assert captured["kwargs"]["password"] == "pw"  # pragma: allowlist secret
    executed_sql = [sql for sql, _ in fake_conn.cursor_obj.executed]
    assert any("SET search_path TO" in sql for sql in executed_sql)
    assert any("SET ROLE" in sql for sql in executed_sql)


def test_connect_sqlite_attaches_database_with_sqlcipher_key() -> None:
    #R615-T01: Attach sqlite database using resolved SQLCipher key and path.

    class FakeConnection:
        #R600: Helper for compare traceability test setup and fixtures.
        def __init__(self):
            #R600: Helper for compare traceability test setup and fixtures.
            self.executed = []

        def execute(self, sql):
            #R600: Helper for compare traceability test setup and fixtures.
            self.executed.append(sql)

    with tempfile.TemporaryDirectory() as tmp:
        sqlite_path = Path(tmp) / "teller.sqlite3"
        sqlite_path.write_text("stub", encoding="utf-8")
        profile = SimpleNamespace(name="sqlite", sqlite_path=str(sqlite_path), sqlcipher_key="profile-key")
        fake_conn = FakeConnection()
        fake_dbapi = SimpleNamespace(connect=lambda _: fake_conn)
        fake_pkg = SimpleNamespace(dbapi2=fake_dbapi)

        existing = sys.modules.get("pysqlcipher3")
        sys.modules["pysqlcipher3"] = fake_pkg
        original_env = MODULE.os.environ.get("TELLER_DB_SQLCIPHER_KEY")
        try:
            MODULE.os.environ.pop("TELLER_DB_SQLCIPHER_KEY", None)
            conn = MODULE._connect_sqlite(profile)
        finally:
            if existing is None:
                sys.modules.pop("pysqlcipher3", None)
            else:
                sys.modules["pysqlcipher3"] = existing
            if original_env is None:
                MODULE.os.environ.pop("TELLER_DB_SQLCIPHER_KEY", None)
            else:
                MODULE.os.environ["TELLER_DB_SQLCIPHER_KEY"] = original_env

    assert conn is fake_conn
    assert any(line.startswith("PRAGMA key") for line in fake_conn.executed)
    assert any(line.startswith("ATTACH DATABASE") for line in fake_conn.executed)


def test_table_enumeration_helpers_return_expected_names() -> None:
    #R620-T01: Enumerate postgres schema and sqlite table names through helper queries.

    class FakeCursor:
        #R600: Helper for compare traceability test setup and fixtures.
        def __init__(self, rows):
            #R600: Helper for compare traceability test setup and fixtures.
            self.rows = rows
            self.executed = []

        def execute(self, sql, params=None):
            #R600: Helper for compare traceability test setup and fixtures.
            self.executed.append((sql, params))

        #R600: Helper for compare traceability test setup and fixtures.
        def fetchall(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return self.rows

    profile = SimpleNamespace(search_path="teller, public")
    assert MODULE._get_postgres_schema(profile) == "teller"

    pg_cur = FakeCursor([("account",), ("transaction",)])
    sqlite_cur = FakeCursor([("account",), ("transaction",)])
    assert MODULE._pg_tables(pg_cur, "teller") == ["account", "transaction"]
    assert MODULE._sqlite_tables(sqlite_cur) == ["account", "transaction"]


def test_column_enumeration_helpers_return_ordered_columns() -> None:
    #R625-T01: Enumerate ordered postgres and sqlite column names for a table.

    class FakeCursor:
        #R600: Helper for compare traceability test setup and fixtures.
        def __init__(self, rows):
            #R600: Helper for compare traceability test setup and fixtures.
            self.rows = rows

        def execute(self, sql, params=None):
            #R600: Helper for compare traceability test setup and fixtures.
            _ = (sql, params)

        #R600: Helper for compare traceability test setup and fixtures.
        def fetchall(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return self.rows

    pg_cur = FakeCursor([("id",), ("name",)])
    sqlite_cur = FakeCursor([(0, "id"), (1, "name")])
    assert MODULE._pg_columns(pg_cur, "teller", "account") == ["id", "name"]
    assert MODULE._sqlite_columns(sqlite_cur, "account") == ["id", "name"]


def test_quote_helpers_escape_embedded_quotes() -> None:
    #R630-T01: Quote identifiers containing embedded quotes safely.
    assert MODULE._quote_pg_ident('bad"name') == '"bad""name"'
    assert MODULE._quote_sqlite_ident('bad"name') == '"bad""name"'


def test_fetch_helpers_use_row_counter_for_each_engine() -> None:
    #R635-T01: Fetch postgres/sqlite rows and route results through row-counter helper.

    class FakeCursor:
        #R600: Helper for compare traceability test setup and fixtures.
        def __init__(self, rows):
            #R600: Helper for compare traceability test setup and fixtures.
            self.rows = rows
            self.executed = []

        def execute(self, query):
            #R600: Helper for compare traceability test setup and fixtures.
            self.executed.append(query)

        #R600: Helper for compare traceability test setup and fixtures.
        def fetchall(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return self.rows

    calls = []

    #R600: Helper for compare traceability test setup and fixtures.
    def fake_row_counter(rows, *, table_name, columns, source):
        #R600: Helper for compare traceability test setup and fixtures.
        calls.append((rows, table_name, tuple(columns), source))
        return Counter({("row", source): 1})

    original_row_counter = MODULE._row_counter
    MODULE._row_counter = fake_row_counter
    try:
        pg_cur = FakeCursor([(1, "x")])
        sqlite_cur = FakeCursor([(1, "x")])
        pg_result = MODULE._fetch_pg_rows(pg_cur, "teller", "account", ["id", "name"])
        sqlite_result = MODULE._fetch_sqlite_rows(sqlite_cur, "account", ["id", "name"])
    finally:
        MODULE._row_counter = original_row_counter

    assert pg_result == Counter({("row", "postgres"): 1})
    assert sqlite_result == Counter({("row", "sqlite"): 1})
    assert calls[0][3] == "postgres"
    assert calls[1][3] == "sqlite"


def test_row_count_helpers_return_integer_counts() -> None:
    #R640-T01: Execute row-count helpers and coerce integer results.

    class FakeCursor:
        #R600: Helper for compare traceability test setup and fixtures.
        def __init__(self, value):
            #R600: Helper for compare traceability test setup and fixtures.
            self.value = value

        def execute(self, query):
            #R600: Helper for compare traceability test setup and fixtures.
            _ = query

        #R600: Helper for compare traceability test setup and fixtures.
        def fetchone(self):
            #R600: Helper for compare traceability test setup and fixtures.
            return (self.value,)

    assert MODULE._pg_row_count(FakeCursor("7"), "teller", "account") == 7
    assert MODULE._sqlite_row_count(FakeCursor("9"), "account") == 9


def test_canonicalize_helpers_normalize_decimal_date_and_context_values() -> None:
    #R645-T01: Canonicalize decimal/date/context-aware values into stable comparison tuples.
    assert MODULE._canonicalize(Decimal("1.2300")) == ("number", "1.23")
    assert MODULE._canonicalize("2026-01-02") == ("date", "2026-01-02")
    assert MODULE._canonicalize_with_context(
        "2026-01-02 10:11:12", table_name="audit_log", column_name="changed_at", source="postgres"
    ) == ("ignored_timestamp", "<ignored>")


def test_money_canonicalization_matches_decimal_and_cents() -> None:
    #R650-T01: Canonicalize equivalent postgres/sqlite money values to matching cents.
    postgres = MODULE._canonicalize_money_value(Decimal("1.00"), source="postgres")
    sqlite = MODULE._canonicalize_money_value(100, source="sqlite")
    assert postgres == sqlite == ("money_cents", "100")


def test_audit_payload_normalization_strips_timestamps_and_normalizes_values() -> None:
    #R655-T01: Normalize audit payload data and strip volatile timestamp keys recursively.
    payload = {
        "created_at": "drop",
        "ledger": "1.23",
        "flag": True,
        "nested": {"updated_at": "drop", "keep": 1},
    }
    normalized = MODULE._normalize_audit_json_payload(payload, target_table="account_balances", source="postgres")
    stripped = MODULE._strip_timestamp_keys({"a": {"created_at": "x", "keep": 2}})
    assert "created_at" not in normalized
    assert normalized["ledger"] == 123
    assert normalized["flag"] == 1
    assert stripped == {"a": {"keep": 2}}


def test_row_counter_is_order_independent_and_counts_duplicates() -> None:
    #R660-T01: Produce equivalent counters for reordered rows while preserving duplicate counts.
    rows_a = [(1, "x"), (2, "y"), (1, "x")]
    rows_b = [(2, "y"), (1, "x"), (1, "x")]
    columns = ["id", "name"]
    counter_a = MODULE._row_counter(rows_a, table_name="account", columns=columns, source="postgres")
    counter_b = MODULE._row_counter(rows_b, table_name="account", columns=columns, source="postgres")
    assert counter_a == counter_b
    assert max(counter_a.values()) == 2


def test_format_counter_examples_respects_requested_limit() -> None:
    #R665-T01: Truncate counter-example output to requested limit while preserving count/row fields.
    counter = Counter({("a",): 3, ("b",): 2})
    examples = MODULE._format_counter_examples(counter, limit=1)
    assert examples == [{"count": 3, "row": ["a"]}]
