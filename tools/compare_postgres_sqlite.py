#!/usr/bin/env python3
#R001: Resolve postgres/sqlite profiles and connect to both databases.
#R005: Compare table and column sets across postgres and sqlite.
#R010: Compare every row and column value for every shared table.
#R015: Emit mismatch details and fail non-zero on any divergence.
"""Systematically compare PostgreSQL and SQLite table parity."""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from pathlib import Path
from typing import Any, Iterable
from uuid import UUID

import psycopg2
import sqlite3
from psycopg2.extensions import connection as PgConnection
from psycopg2.extensions import cursor as PgCursor
from sqlite3 import Connection as SqliteConnection

# Allow direct execution regardless of script directory.
#R600: Discover repository root from script location.
def _discover_repo_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "src" / "teller").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate repository root from script path: {start}")


REPO_ROOT = _discover_repo_root(Path(__file__).resolve().parent)
SRC_ROOT = REPO_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from teller.teller_db import _read_password  # noqa: E402
from teller.teller_db_profile import ProfileError, ResolvedProfile, reset_profile_cache, resolve_profile  # noqa: E402

IGNORED_ROW_COMPARE_COLUMNS = {"created_at", "updated_at"}
USD_MONEY_COLUMNS = {
    "account_balances": {"ledger", "available"},
    "transaction": {"amount", "running_balance"},
}


@dataclass(frozen=True)
class TableDiff:
    table: str
    issue: str
    details: str


#R605: Resolve named database profile with env override handling.
def _resolve_named_profile(profile_name: str) -> ResolvedProfile:
    original = os.environ.get("TELLER_DB_PROFILE")
    try:
        os.environ["TELLER_DB_PROFILE"] = profile_name
        reset_profile_cache()
        return resolve_profile()
    finally:
        if original is None:
            os.environ.pop("TELLER_DB_PROFILE", None)
        else:
            os.environ["TELLER_DB_PROFILE"] = original
        reset_profile_cache()


#R610: Open PostgreSQL connection from resolved profile settings.
def _connect_postgres(profile: ResolvedProfile) -> PgConnection:
    password = _read_password(profile)
    connect_args: dict[str, Any] = {
        "host": profile.host,
        "port": profile.port,
        "dbname": profile.dbname,
        "user": profile.user,
        "password": password,
    }
    if profile.sslmode and profile.sslmode != "disable":
        connect_args["sslmode"] = profile.sslmode
    conn = psycopg2.connect(**connect_args)
    search_path = ",".join(part.strip() for part in profile.search_path.split(",") if part.strip()) or "teller"
    with conn.cursor() as cur:
        cur.execute("SELECT string_agg(quote_ident(trim(schema_name)), ',') FROM unnest(string_to_array(%s, ',')) AS schema_name", (search_path,))
        quoted_path = cur.fetchone()[0]
        if not quoted_path:
            raise RuntimeError("Resolved PostgreSQL search_path is empty.")
        cur.execute(f"SET search_path TO {quoted_path}")
        if profile.runtime_role:
            cur.execute("SELECT quote_ident(%s)", (profile.runtime_role,))
            quoted_role = cur.fetchone()[0]
            cur.execute(f"SET ROLE {quoted_role}")
    return conn


#R615: Open SQLite SQLCipher connection from resolved profile settings.
def _connect_sqlite(profile: ResolvedProfile) -> SqliteConnection:
    sqlite_path = profile.sqlite_path or str(Path.cwd() / ".database" / "teller.sqlite3")
    if not Path(sqlite_path).exists():
        raise FileNotFoundError(f"SQLite database file not found: {sqlite_path}")

    sqlcipher_key = os.environ.get("TELLER_DB_SQLCIPHER_KEY") or profile.sqlcipher_key
    if not sqlcipher_key:
        raise RuntimeError(
            f"Profile {profile.name!r} is missing sqlcipher_key. "
            "Set TELLER_DB_SQLCIPHER_KEY or populate sqlcipher_key on the profile item."
        )
    try:
        from pysqlcipher3 import dbapi2 as sqlcipher_dbapi
    except ImportError as exc:
        raise RuntimeError(
            "pysqlcipher3 is required for sqlite parity checks. "
            "Run ./04_load_requirements.sh after installing prerequisites."
        ) from exc

    escaped_key = sqlcipher_key.replace("'", "''")
    escaped_path = sqlite_path.replace("'", "''")
    conn = sqlcipher_dbapi.connect(":memory:")
    conn.execute(f"PRAGMA key = '{escaped_key}'")
    conn.execute(f"ATTACH DATABASE '{escaped_path}' AS teller KEY '{escaped_key}'")
    return conn


#R620: Resolve active PostgreSQL schema for table discovery.
def _get_postgres_schema(profile: ResolvedProfile) -> str:
    first_schema = next((part.strip() for part in profile.search_path.split(",") if part.strip()), "")
    return first_schema or "teller"


#R620: Enumerate PostgreSQL tables in the resolved schema.
def _pg_tables(cur: PgCursor, schema_name: str) -> list[str]:
    cur.execute(
        """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = %s
          AND table_type = 'BASE TABLE'
        ORDER BY table_name
        """,
        (schema_name,),
    )
    return [row[0] for row in cur.fetchall()]


#R620: Enumerate SQLite tables in attached teller catalog.
def _sqlite_tables(cur: sqlite3.Cursor) -> list[str]:
    cur.execute(
        """
        SELECT name
        FROM teller.sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    )
    return [row[0] for row in cur.fetchall()]


#R625: Enumerate ordered PostgreSQL column names for a table.
def _pg_columns(cur: PgCursor, schema_name: str, table_name: str) -> list[str]:
    cur.execute(
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = %s
          AND table_name = %s
        ORDER BY ordinal_position
        """,
        (schema_name, table_name),
    )
    return [row[0] for row in cur.fetchall()]


#R625: Enumerate ordered SQLite column names for a table.
def _sqlite_columns(cur: sqlite3.Cursor, table_name: str) -> list[str]:
    escaped = table_name.replace("'", "''")
    cur.execute(f"PRAGMA teller.table_info('{escaped}')")
    return [row[1] for row in cur.fetchall()]


#R630: Quote PostgreSQL identifiers safely for SQL generation.
def _quote_pg_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


#R630: Quote SQLite identifiers safely for SQL generation.
def _quote_sqlite_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


#R645: Canonicalize scalar and structured values for cross-engine comparison.
def _canonicalize(value: Any) -> Any:
    if isinstance(value, str):
        # Align date/datetime textual values with typed values from the other engine.
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            return ("date", value)
        if re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?", value):
            return ("datetime", value)
        candidate = value.strip()
        if candidate.startswith("{") or candidate.startswith("["):
            try:
                parsed_json = json.loads(candidate)
            except ValueError:
                pass
            else:
                parsed_json = _strip_timestamp_keys(parsed_json)
                return ("json", json.dumps(parsed_json, sort_keys=True, separators=(",", ":"), default=str))
        return ("str", value)
    if value is None:
        return ("null", None)
    if isinstance(value, bool):
        return ("number", "1" if value else "0")
    if isinstance(value, int):
        return ("number", str(value))
    if isinstance(value, float):
        return ("number", _normalize_decimal_str(Decimal(str(value))))
    if isinstance(value, Decimal):
        return ("number", _normalize_decimal_str(value))
    if isinstance(value, datetime):
        return ("datetime", value.isoformat(sep=" ", timespec="microseconds"))
    if isinstance(value, date):
        return ("date", value.isoformat())
    if isinstance(value, time):
        return ("time", value.isoformat(timespec="microseconds"))
    if isinstance(value, (bytes, bytearray, memoryview)):
        return ("bytes", bytes(value).hex())
    if isinstance(value, UUID):
        return ("uuid", str(value))
    if isinstance(value, (dict, list)):
        return ("json", json.dumps(_strip_timestamp_keys(value), sort_keys=True, separators=(",", ":"), default=str))
    return ("repr", repr(value))


#R655: Strip volatile timestamp keys from nested payload structures.
def _strip_timestamp_keys(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: _strip_timestamp_keys(val)
            for key, val in value.items()
            if key not in {"created_at", "updated_at"}
        }
    if isinstance(value, list):
        return [_strip_timestamp_keys(item) for item in value]
    return value


#R645: Normalize decimal representations for stable value comparison.
def _normalize_decimal_str(value: Decimal) -> str:
    normalized = format(value.normalize(), "f")
    if "." in normalized:
        normalized = normalized.rstrip("0").rstrip(".")
    return normalized or "0"


#R650: Canonicalize money values into unified cents representation.
def _canonicalize_money_value(value: Any, *, source: str) -> tuple[str, str]:
    if value is None:
        return ("null", None)
    if source == "sqlite":
        # SQLite stores money as integer cents.
        cents = int(value)
    else:
        # PostgreSQL stores money as decimal dollars.
        cents = int((Decimal(str(value)) * Decimal("100")).quantize(Decimal("1")))
    return ("money_cents", str(cents))


#R655: Normalize audit JSON payloads before parity comparison.
def _normalize_audit_json_payload(value: Any, *, target_table: str, source: str, current_key: str | None = None) -> Any:
    if isinstance(value, dict):
        normalized: dict[str, Any] = {}
        for key, nested in value.items():
            if key in {"created_at", "updated_at"}:
                continue
            normalized[key] = _normalize_audit_json_payload(
                nested,
                target_table=target_table,
                source=source,
                current_key=key,
            )
        return normalized
    if isinstance(value, list):
        return [
            _normalize_audit_json_payload(item, target_table=target_table, source=source, current_key=current_key)
            for item in value
        ]
    if isinstance(value, bool):
        return 1 if value else 0
    if current_key and current_key in USD_MONEY_COLUMNS.get(target_table, set()):
        canonical = _canonicalize_money_value(value, source=source)
        if canonical[0] == "null":
            return None
        return int(canonical[1])
    return value


#R645: Canonicalize values with table/column-specific comparison context.
def _canonicalize_with_context(
    value: Any,
    *,
    table_name: str,
    column_name: str,
    source: str,
    row_values: dict[str, Any] | None = None,
) -> Any:
    if table_name == "audit_log" and column_name == "changed_at":
        return ("ignored_timestamp", "<ignored>")
    if table_name == "audit_log" and column_name in {"new_data", "old_data"}:
        if value is None:
            return ("null", None)
        payload = value
        if isinstance(value, str):
            try:
                payload = json.loads(value)
            except ValueError:
                return _canonicalize(value)
        target_table = ""
        if row_values is not None and row_values.get("table_name") is not None:
            target_table = str(row_values["table_name"])
        normalized_payload = _normalize_audit_json_payload(payload, target_table=target_table, source=source)
        return ("json", json.dumps(normalized_payload, sort_keys=True, separators=(",", ":"), default=str))
    if column_name in USD_MONEY_COLUMNS.get(table_name, set()):
        return _canonicalize_money_value(value, source=source)
    return _canonicalize(value)


#R660: Build order-independent row multisets with duplicate counts.
def _row_counter(
    rows: Iterable[tuple[Any, ...]],
    *,
    table_name: str,
    columns: list[str],
    source: str,
) -> collections.Counter[tuple[Any, ...]]:
    counter: collections.Counter[tuple[Any, ...]] = collections.Counter()
    for row in rows:
        row_values = {column_name: value for column_name, value in zip(columns, row)}
        canonical_row = tuple(
            _canonicalize_with_context(
                value,
                table_name=table_name,
                column_name=column_name,
                source=source,
                row_values=row_values,
            )
            for column_name, value in zip(columns, row)
        )
        counter[canonical_row] += 1
    return counter


#R635: Fetch canonicalized row multiset from PostgreSQL table data.
def _fetch_pg_rows(cur: PgCursor, schema_name: str, table_name: str, columns: list[str]) -> collections.Counter[tuple[Any, ...]]:
    projected = ", ".join(_quote_pg_ident(column) for column in columns)
    query = f"SELECT {projected} FROM {_quote_pg_ident(schema_name)}.{_quote_pg_ident(table_name)}"
    cur.execute(query)
    return _row_counter(cur.fetchall(), table_name=table_name, columns=columns, source="postgres")


#R635: Fetch canonicalized row multiset from SQLite table data.
def _fetch_sqlite_rows(cur: sqlite3.Cursor, table_name: str, columns: list[str]) -> collections.Counter[tuple[Any, ...]]:
    projected = ", ".join(_quote_sqlite_ident(column) for column in columns)
    query = f"SELECT {projected} FROM teller.{_quote_sqlite_ident(table_name)}"
    cur.execute(query)
    return _row_counter(cur.fetchall(), table_name=table_name, columns=columns, source="sqlite")


#R640: Count PostgreSQL rows for shared table parity checks.
def _pg_row_count(cur: PgCursor, schema_name: str, table_name: str) -> int:
    query = f"SELECT COUNT(*) FROM {_quote_pg_ident(schema_name)}.{_quote_pg_ident(table_name)}"
    cur.execute(query)
    return int(cur.fetchone()[0])


#R640: Count SQLite rows for shared table parity checks.
def _sqlite_row_count(cur: sqlite3.Cursor, table_name: str) -> int:
    query = f"SELECT COUNT(*) FROM teller.{_quote_sqlite_ident(table_name)}"
    cur.execute(query)
    return int(cur.fetchone()[0])


#R665: Format bounded counter-example rows for mismatch reporting.
def _format_counter_examples(counter: collections.Counter[tuple[Any, ...]], limit: int) -> list[dict[str, Any]]:
    examples: list[dict[str, Any]] = []
    for row, count in counter.most_common(limit):
        examples.append({"count": count, "row": list(row)})
    return examples


#R005: Compare table and column coverage between both database engines.
#R010: Compare canonicalized row content for all shared tables.
def compare_databases(
    postgres_profile: ResolvedProfile,
    sqlite_profile: ResolvedProfile,
    *,
    max_row_examples: int,
) -> list[TableDiff]:
    diffs: list[TableDiff] = []
    pg_schema = _get_postgres_schema(postgres_profile)

    with _connect_postgres(postgres_profile) as pg_conn, _connect_sqlite(sqlite_profile) as sqlite_conn:
        with pg_conn.cursor() as pg_cur:
            sqlite_cur = sqlite_conn.cursor()

            pg_tables = _pg_tables(pg_cur, pg_schema)
            sqlite_tables = _sqlite_tables(sqlite_cur)
            pg_set = set(pg_tables)
            sqlite_set = set(sqlite_tables)
            only_pg = sorted(pg_set - sqlite_set)
            only_sqlite = sorted(sqlite_set - pg_set)
            if only_pg:
                diffs.append(TableDiff(table="*", issue="missing_in_sqlite", details=", ".join(only_pg)))
            if only_sqlite:
                diffs.append(TableDiff(table="*", issue="missing_in_postgres", details=", ".join(only_sqlite)))

            for table_name in sorted(pg_set & sqlite_set):
                pg_cols = _pg_columns(pg_cur, pg_schema, table_name)
                sqlite_cols = _sqlite_columns(sqlite_cur, table_name)
                pg_col_set = set(pg_cols)
                sqlite_col_set = set(sqlite_cols)
                if pg_col_set != sqlite_col_set:
                    only_pg_cols = sorted(pg_col_set - sqlite_col_set)
                    only_sqlite_cols = sorted(sqlite_col_set - pg_col_set)
                    diffs.append(
                        TableDiff(
                            table=table_name,
                            issue="column_mismatch",
                            details=(
                                f"missing_in_sqlite={only_pg_cols} "
                                f"missing_in_postgres={only_sqlite_cols}"
                            ),
                        )
                    )
                    continue
                if pg_cols != sqlite_cols:
                    diffs.append(
                        TableDiff(
                            table=table_name,
                            issue="column_order_mismatch",
                            details=f"postgres={pg_cols} sqlite={sqlite_cols}",
                        )
                    )
                # Keep value comparison deterministic even when order mismatch is flagged.
                compare_columns = sorted(column for column in pg_col_set if column not in IGNORED_ROW_COMPARE_COLUMNS)

                if not compare_columns:
                    pg_count = _pg_row_count(pg_cur, pg_schema, table_name)
                    sqlite_count = _sqlite_row_count(sqlite_cur, table_name)
                    if pg_count != sqlite_count:
                        details = {"postgres_count": pg_count, "sqlite_count": sqlite_count}
                        diffs.append(
                            TableDiff(
                                table=table_name,
                                issue="row_count_mismatch",
                                details=json.dumps(details),
                            )
                        )
                    continue

                pg_rows = _fetch_pg_rows(pg_cur, pg_schema, table_name, compare_columns)
                sqlite_rows = _fetch_sqlite_rows(sqlite_cur, table_name, compare_columns)
                if pg_rows == sqlite_rows:
                    continue

                missing_in_sqlite = pg_rows - sqlite_rows
                missing_in_postgres = sqlite_rows - pg_rows
                details = {
                    "missing_in_sqlite_total": sum(missing_in_sqlite.values()),
                    "missing_in_postgres_total": sum(missing_in_postgres.values()),
                    "missing_in_sqlite_examples": _format_counter_examples(missing_in_sqlite, max_row_examples),
                    "missing_in_postgres_examples": _format_counter_examples(missing_in_postgres, max_row_examples),
                }
                diffs.append(TableDiff(table=table_name, issue="row_mismatch", details=json.dumps(details, default=str)))

    return diffs


#R001: Parse profile and reporting options for dual-engine comparison runs.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare every table/column/row between Postgres and SQLite Teller databases.")
    parser.add_argument(
        "--postgres-profile",
        default="postgres",
        help="DB profile name for PostgreSQL comparison source (default: postgres).",
    )
    parser.add_argument(
        "--sqlite-profile",
        default="sqlite",
        help="DB profile name for SQLite comparison target (default: sqlite).",
    )
    parser.add_argument(
        "--max-row-examples",
        type=int,
        default=5,
        help="Max mismatch row examples per table side (default: 5).",
    )
    parser.add_argument(
        "--output-json",
        default="artifacts/quality/reports/postgres-sqlite-parity.json",
        help="Path for machine-readable parity report.",
    )
    return parser.parse_args()


#R015: Emit machine-readable mismatch report and process exit status.
def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    args = parse_args()
    output_path = Path(args.output_json)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        postgres_profile = _resolve_named_profile(args.postgres_profile)
        sqlite_profile = _resolve_named_profile(args.sqlite_profile)
    except ProfileError as exc:
        print(f"Profile resolution failed: {exc}")
        return 2

    if postgres_profile.target == "sqlite":
        print(f"Profile {postgres_profile.name!r} resolved to sqlite target; expected postgres/local/managed target.")
        return 2
    if sqlite_profile.target != "sqlite":
        print(f"Profile {sqlite_profile.name!r} did not resolve to sqlite target.")
        return 2
    if args.max_row_examples < 1:
        print("--max-row-examples must be >= 1")
        return 2

    diffs = compare_databases(postgres_profile, sqlite_profile, max_row_examples=args.max_row_examples)
    report = {
        "postgres_profile": postgres_profile.name,
        "sqlite_profile": sqlite_profile.name,
        "postgres_target": postgres_profile.target,
        "sqlite_target": sqlite_profile.target,
        "postgres_search_path": postgres_profile.search_path,
        "sqlite_path": sqlite_profile.sqlite_path,
        "diff_count": len(diffs),
        "diffs": [{"table": diff.table, "issue": diff.issue, "details": diff.details} for diff in diffs],
    }
    output_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if not diffs:
        print("Postgres and SQLite are identical across every compared table/column/row.")
        print(f"Report: {output_path}")
        return 0

    print(f"Parity check failed with {len(diffs)} differences.")
    for diff in diffs:
        print(f"- [{diff.issue}] {diff.table}: {diff.details}")
    print(f"Report: {output_path}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
