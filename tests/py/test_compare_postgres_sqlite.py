"""Traceability coverage tests for compare_postgres_sqlite requirements."""

from pathlib import Path


def _script_path() -> Path:
    return Path("tools/compare_postgres_sqlite.py")


def test_r001_cli_exists() -> None:
    #R001-T01
    assert _script_path().is_file()


def test_r005_uses_schema_comparison_terms() -> None:
    #R005-T01
    text = _script_path().read_text(encoding="utf-8")
    assert "column" in text.lower()


def test_r010_uses_row_comparison_terms() -> None:
    #R010-T01
    text = _script_path().read_text(encoding="utf-8")
    assert "row" in text.lower()


def test_r015_supports_json_output_flag() -> None:
    #R015-T01
    text = _script_path().read_text(encoding="utf-8")
    assert "--output-json" in text
