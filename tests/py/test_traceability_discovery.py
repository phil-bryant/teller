from __future__ import annotations

from pathlib import Path

from traceability.discovery import discover_test_files_for_requirements, extract_source_files_from_analogous_tree


def test_extract_source_files_from_analogous_tree_matches_stem(tmp_path: Path) -> None:
    repo_root = tmp_path
    req_dir = repo_root / "requirements" / "demo"
    req_dir.mkdir(parents=True)
    req_file = req_dir / "tool-requirements.md"
    req_file.write_text("## Scope\n", encoding="utf-8")
    source = repo_root / "demo" / "tool.py"
    source.parent.mkdir(parents=True)
    source.write_text("# source\n", encoding="utf-8")

    results = extract_source_files_from_analogous_tree(req_file, repo_root)
    assert results == ["demo/tool.py"]


def test_discover_test_files_for_requirements_prefers_matching_python_test(tmp_path: Path) -> None:
    repo_root = tmp_path
    req_file = repo_root / "requirements" / "teller" / "teller_object-requirements.md"
    req_file.parent.mkdir(parents=True)
    req_file.write_text("## Scope\n", encoding="utf-8")

    source_file = repo_root / "src" / "teller" / "teller_object.py"
    source_file.parent.mkdir(parents=True)
    source_file.write_text("# source\n", encoding="utf-8")

    matching_test = repo_root / "tests" / "py" / "test_teller_object.py"
    matching_test.parent.mkdir(parents=True)
    matching_test.write_text("# test\n", encoding="utf-8")

    nonmatching_test = repo_root / "tests" / "py" / "test_teller_classification_api.py"
    nonmatching_test.write_text("# test\n", encoding="utf-8")

    default_tests, ui_tests = discover_test_files_for_requirements(
        req_file, ["src/teller/teller_object.py"], repo_root
    )
    assert any(path.endswith("/tests/py/test_teller_object.py") for path in default_tests)
    assert not any(path.endswith("/tests/py/test_teller_classification_api.py") for path in default_tests)
    assert ui_tests == []
