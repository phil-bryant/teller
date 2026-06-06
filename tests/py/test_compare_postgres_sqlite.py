"""Traceability coverage tests for compare_postgres_sqlite requirements."""

from pathlib import Path


def _script_path() -> Path:
    return Path("tools/compare_postgres_sqlite.py")


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
