from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable


REQ_ID_PATTERN = re.compile(r"^R\d{3}(?:-\d{3})*")
REQ_LINE_PATTERN = re.compile(r"^(R\d{3}(?:-\d{3})*)\s+Statement:")
SOURCE_TAG_PATTERN = re.compile(r"#(R\d{3}(?:-\d{3})*)")
SCOPED_SOURCE_TAG_PATTERN = re.compile(r"#(R\d{3}(?:-\d{3})*):\s*[A-Za-z0-9_]")
NUMBERED_TEST_TAG_PATTERN = re.compile(r"#(R\d{3}(?:-\d{3})*-T\d{2})")
NUMBERED_BULLET_PATTERN = re.compile(r"^-\s+(R\d{3}(?:-\d{3})*)-T(\d{2})\s*:")
BACKTICK_TOKEN_PATTERN = re.compile(r"`([^`]+)`")

UI_HINT_PATTERN = re.compile(r"ui[\s-]*test|xcuitest|xctest[\s-]*ui|ui[\s-]*mode", flags=re.IGNORECASE)

ALLOWED_SCOPE_FILE_EXTS = {
    "sh",
    "py",
    "swift",
    "sql",
    "c",
    "cc",
    "cpp",
    "cxx",
    "m",
    "mm",
    "h",
    "hpp",
}
ALLOWED_SCOPE_FILENAMES = {"Makefile", ".gitignore"}

_BATS_START_RE = re.compile(
    r"^\s*(?:@test\b.*\{\s*$|bats_test_function\b.*\{\s*$|[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{\s*$)"
)
_PYTHON_START_RE = re.compile(r"^\s*def\s+test[_A-Za-z0-9]*\s*\(")
_SWIFT_START_RE = re.compile(r"^\s*func\s+test[_A-Za-z0-9]*\s*\(")


def extract_requirement_ids(text: str) -> list[str]:
    ids = set()
    for line in text.splitlines():
        match = REQ_ID_PATTERN.match(line)
        if match:
            ids.add(match.group(0))
    return sorted(ids)


def extract_source_ids(text: str) -> list[str]:
    ids = {match.group(1) for match in SOURCE_TAG_PATTERN.finditer(text)}
    return sorted(ids)


def extract_scoped_source_ids(text: str) -> list[str]:
    ids = {match.group(1) for match in SCOPED_SOURCE_TAG_PATTERN.finditer(text)}
    return sorted(ids)


def detect_header_bundle_tags(text: str, max_lines: int = 40) -> str | None:
    for idx, raw_line in enumerate(text.splitlines()[:max_lines], start=1):
        total = len(SOURCE_TAG_PATTERN.findall(raw_line))
        scoped = len(re.findall(r"#R\d{3}(?:-\d{3})*:", raw_line))
        if total >= 3 and scoped == 0:
            return f"{idx}:{raw_line}"
    return None


def extract_source_files_from_requirements(text: str) -> list[str]:
    files: set[str] = set()
    in_scope = False
    for raw_line in text.splitlines():
        line = raw_line.rstrip("\n")
        stripped = line.strip()
        if stripped == "## Scope":
            in_scope = True
            continue
        if stripped.startswith("## ") and in_scope:
            in_scope = False
        if REQ_ID_PATTERN.match(stripped) and in_scope:
            in_scope = False
        if not in_scope:
            continue
        for match in BACKTICK_TOKEN_PATTERN.finditer(line):
            token = match.group(1)
            if token.startswith("./"):
                token = token[2:]
            path = Path(token)
            ext = path.suffix.lower().lstrip(".")
            if ext in ALLOWED_SCOPE_FILE_EXTS or token in ALLOWED_SCOPE_FILENAMES:
                files.add(token)
    return sorted(files)


def extract_ui_required_ids(text: str) -> list[str]:
    ids = set()
    for line in text.splitlines():
        lowered = line.lower()
        if not re.match(r"^r\d{3}(?:-\d{3})*\s+statement:", lowered):
            continue
        rid = line.split(None, 1)[0].upper()
        if UI_HINT_PATTERN.search(lowered):
            ids.add(rid)
    return sorted(ids)


def extract_numbered_requirement_test_ids(text: str) -> list[str]:
    current_requirement_id: str | None = None
    in_tests = False
    ids: set[str] = set()
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        req_match = REQ_LINE_PATTERN.match(stripped)
        if req_match:
            current_requirement_id = req_match.group(1)
            in_tests = False
            continue
        if stripped == "Tests:":
            in_tests = True
            continue
        if in_tests and stripped.startswith("- "):
            match = NUMBERED_BULLET_PATTERN.match(stripped)
            if match and current_requirement_id and match.group(1) == current_requirement_id:
                ids.add(f"{match.group(1)}-T{match.group(2)}")
            continue
        if in_tests and stripped and not stripped.startswith("- "):
            in_tests = False
    return sorted(ids)


def verify_requirements_numbered_test_bullets(text: str, requirements_file: str) -> list[str]:
    current_requirement_id: str | None = None
    in_tests = False
    seen_numbers: dict[str, list[int]] = {}
    issues: list[str] = []
    for idx, raw_line in enumerate(text.splitlines(), start=1):
        stripped = raw_line.strip()
        req_match = REQ_LINE_PATTERN.match(stripped)
        if req_match:
            current_requirement_id = req_match.group(1)
            in_tests = False
            seen_numbers.setdefault(current_requirement_id, [])
            continue
        if stripped == "Tests:":
            in_tests = True
            continue
        if in_tests and stripped.startswith("- "):
            match = NUMBERED_BULLET_PATTERN.match(stripped)
            if not match:
                expected = ""
                if current_requirement_id:
                    next_number = len(seen_numbers.get(current_requirement_id, [])) + 1
                    expected = f" (expected prefix: {current_requirement_id}-T{next_number:02d})"
                issues.append(
                    f"{requirements_file}:{idx}: unnumbered/invalid test bullet under Tests:{expected}"
                )
                continue
            bullet_requirement_id = match.group(1)
            bullet_test_number = int(match.group(2))
            if current_requirement_id and bullet_requirement_id != current_requirement_id:
                issues.append(
                    f"{requirements_file}:{idx}: test bullet {bullet_requirement_id}-T{bullet_test_number:02d} does not match requirement {current_requirement_id}"
                )
                continue
            if current_requirement_id:
                seen_numbers[current_requirement_id].append(bullet_test_number)
            continue
        if in_tests and stripped and not stripped.startswith("- "):
            in_tests = False
    return issues


def extract_numbered_test_ids(test_file: Path) -> tuple[list[str], list[str]]:
    suffix = test_file.suffix.lower()
    is_bats = suffix == ".bats"
    is_python = suffix == ".py"
    is_swift = suffix == ".swift"
    enforce_scoped = is_bats or is_python or is_swift

    if not test_file.exists():
        return [], []

    ids: set[str] = set()
    misplaced: list[str] = []
    lines = test_file.read_text(encoding="utf-8").splitlines()

    if not enforce_scoped:
        for line in lines:
            for match in NUMBERED_TEST_TAG_PATTERN.finditer(line):
                ids.add(match.group(1))
        return sorted(ids), misplaced

    in_test_block = False
    brace_depth = 0
    block_indent = 0
    idx = 0
    while idx < len(lines):
        line_number = idx + 1
        line = lines[idx]
        line_tags = [match.group(1) for match in NUMBERED_TEST_TAG_PATTERN.finditer(line)]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" \t"))

        if is_python:
            while True:
                if not in_test_block and _PYTHON_START_RE.search(line):
                    in_test_block = True
                    block_indent = indent
                    for tag in line_tags:
                        ids.add(tag)
                    break
                if in_test_block:
                    if stripped and indent <= block_indent and not _PYTHON_START_RE.search(line):
                        in_test_block = False
                        continue
                    for tag in line_tags:
                        ids.add(tag)
                    break
                for tag in line_tags:
                    misplaced.append(f"{test_file}:{line_number}: #{tag}")
                break
        elif is_bats:
            if not in_test_block and _BATS_START_RE.search(line):
                in_test_block = True
            if in_test_block:
                for tag in line_tags:
                    ids.add(tag)
                brace_depth += line.count("{")
                brace_depth -= line.count("}")
                if brace_depth <= 0:
                    in_test_block = False
                    brace_depth = 0
            else:
                for tag in line_tags:
                    misplaced.append(f"{test_file}:{line_number}: #{tag}")
        elif is_swift:
            if not in_test_block and _SWIFT_START_RE.search(line):
                in_test_block = True
            if in_test_block:
                for tag in line_tags:
                    ids.add(tag)
                brace_depth += line.count("{")
                brace_depth -= line.count("}")
                if brace_depth <= 0:
                    in_test_block = False
                    brace_depth = 0
            else:
                for tag in line_tags:
                    misplaced.append(f"{test_file}:{line_number}: #{tag}")

        idx += 1

    return sorted(ids), misplaced


def format_bulleted(items: Iterable[str], prefix: str = "  - ") -> str:
    return "\n".join(f"{prefix}{item}" for item in items)
