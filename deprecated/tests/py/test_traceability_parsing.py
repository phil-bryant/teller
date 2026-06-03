from __future__ import annotations

from pathlib import Path

from traceability.parsing import (
    detect_header_bundle_tags,
    extract_numbered_test_ids,
    extract_requirement_ids,
    extract_source_files_from_requirements,
    verify_requirements_numbered_test_bullets,
)


def test_extract_source_files_from_requirements_scope_only() -> None:
    text = """## Scope
Applies to `foo.sh`, `docs.md`, and `src/mod.py`.
R001 Statement: One.
Applies to `ignored_after_requirement.py`.
"""
    assert extract_source_files_from_requirements(text) == ["foo.sh", "src/mod.py"]


def test_detect_header_bundle_tags_finds_anti_cheat_pattern() -> None:
    text = """#!/usr/bin/env bash
# #R001 #R002 #R003
echo "x"
"""
    assert detect_header_bundle_tags(text) == "2:# #R001 #R002 #R003"


def test_extract_numbered_test_ids_tracks_misplaced_header_tags(tmp_path: Path) -> None:
    test_file = tmp_path / "sample.bats"
    test_file.write_text(
        """# #R100-T01 misplaced
@test "ok" {
  #R100-T02 in-body
  true
}
""",
        encoding="utf-8",
    )
    ids, misplaced = extract_numbered_test_ids(test_file)
    assert ids == ["R100-T02"]
    assert misplaced == [f"{test_file}:1: #R100-T01"]


def test_verify_requirements_numbered_test_bullets_reports_invalid_lines() -> None:
    text = """R001 Statement: One.
Tests:
- Missing prefix.
"""
    issues = verify_requirements_numbered_test_bullets(text, "requirements/sample.md")
    assert len(issues) == 1
    assert "unnumbered/invalid test bullet" in issues[0]


def test_extract_requirement_ids_parses_hierarchical_ids() -> None:
    text = "R001 Statement: One.\nR001-010 Statement: Two.\n"
    assert extract_requirement_ids(text) == ["R001", "R001-010"]
