from __future__ import annotations

import os
from pathlib import Path

from .parsing import extract_source_files_from_requirements


ALLOWED_SOURCE_EXTS = {".sh", ".py", ".swift", ".sql", ".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".h", ".hpp"}
ALLOWED_SOURCE_NAMES = {"Makefile", ".gitignore"}


def list_requirements_files(repo_root: Path) -> list[Path]:
    return sorted({path for path in (repo_root / "requirements").rglob("*-requirements.md") if path.is_file()})


def extract_source_files_from_requirements_path(requirements_file: Path) -> list[str]:
    return extract_source_files_from_requirements(requirements_file.read_text(encoding="utf-8"))


def extract_source_files_from_analogous_tree(requirements_file: Path, repo_root: Path) -> list[str]:
    rel_path = requirements_file.relative_to(repo_root / "requirements")
    req_base = rel_path.name
    source_stem = req_base.removesuffix("-requirements.md")
    if source_stem == req_base:
        return []
    search_root = repo_root / rel_path.parent
    if not search_root.exists():
        search_root = repo_root

    matches: set[str] = set()
    for root, _dirs, files in os.walk(search_root):
        for name in files:
            path = Path(root) / name
            if path.suffix and path.stem == source_stem and path.suffix.lstrip(".") in {e.lstrip(".") for e in ALLOWED_SOURCE_EXTS}:
                matches.add(path.relative_to(repo_root).as_posix())
            if name == source_stem and name in ALLOWED_SOURCE_NAMES:
                matches.add(path.relative_to(repo_root).as_posix())
    return sorted(matches)


def discover_test_files_for_requirements(
    requirements_file: Path, source_files: list[str], repo_root: Path
) -> tuple[list[str], list[str]]:
    seen_default: set[Path] = set()
    seen_ui: set[Path] = set()
    default_results: list[Path] = []
    ui_results: list[Path] = []

    def add_path(path: str, lane: str) -> None:
        candidate = (repo_root / path) if not Path(path).is_absolute() else Path(path)
        if not candidate.is_file():
            return
        normalized = candidate.resolve()
        if lane == "ui":
            if normalized not in seen_ui:
                seen_ui.add(normalized)
                ui_results.append(normalized)
            return
        if normalized not in seen_default:
            seen_default.add(normalized)
            default_results.append(normalized)

    def collect_swift_lane(root_dir: str, lane: str, stem: str = "") -> None:
        root_path = repo_root / root_dir
        if not root_path.is_dir():
            return
        for path in root_path.rglob("*.swift"):
            if stem and stem not in path.name:
                continue
            add_path(path.relative_to(repo_root).as_posix(), lane)

    requirements_stem = requirements_file.name.removesuffix("-requirements.md")
    add_path(f"tests/sh/{requirements_stem}.bats", "default")

    for source_file in source_files:
        source_path = Path(source_file)
        if source_path.is_absolute():
            try:
                source_path = source_path.resolve().relative_to(repo_root.resolve())
            except ValueError:
                pass
        source_norm = source_path.as_posix()
        base = source_path.name
        stem = source_path.stem
        ext = source_path.suffix.lower()
        if ext == ".sh":
            add_path(f"tests/sh/{stem}.bats", "default")
        if base == "Makefile":
            add_path("tests/sh/Makefile.bats", "default")
        if ext == ".py":
            if source_norm.startswith("src/teller/"):
                add_path(f"tests/py/test_{stem}.py", "default")
            elif source_norm.startswith(tuple(f"{n:02d}_" for n in range(100))):
                add_path(f"tests/sh/{stem}.bats", "default")
            else:
                add_path(f"tests/py/test_{stem}.py", "default")
        if ext == ".sql":
            add_path(f"tests/sh/{stem}.bats", "default")
            add_path(f"tests/sql/{stem}.sql", "default")
            add_path(f"tests/sql/test_{stem}.sql", "default")
        if ext == ".swift" and source_norm.startswith("src/macos-ui/Sources/"):
            collect_swift_lane("src/macos-ui/Tests", "default", stem=stem)
            collect_swift_lane("src/macos-ui/UITests", "ui", stem=stem)

    if requirements_file.as_posix().startswith((repo_root / "requirements/macos-ui/").as_posix()):
        collect_swift_lane("src/macos-ui/UITests", "ui")

    if requirements_file.name == "t14_run_macos_ui_regression_tests-requirements.md":
        collect_swift_lane("src/macos-ui/UITests", "ui")

    return sorted(path.as_posix() for path in default_results), sorted(path.as_posix() for path in ui_results)


def list_repository_software_files(repo_root: Path, excluded_path: Path | None = None) -> list[str]:
    excluded_real = excluded_path.resolve() if excluded_path else None
    excluded_dirs = {
        ".git",
        ".cursor",
        "requirements",
        "tests",
        "Tests",
        "bin",
        "backups",
        "artifacts",
        ".gocache",
        ".gomodcache",
        ".build",
        "__pycache__",
        ".venv",
        "venv",
        "site-packages",
        ".mypy_cache",
        ".tox",
        "node_modules",
        ".gradle",
        "Pods",
        ".swiftpm",
        "teller-venv",
        ".derivedData-ui-tests",
    }
    excluded_dir_prefixes = (".derivedData",)
    excluded_relative_paths = {"storage/schema.sql"}
    excluded_relative_prefixes = ("storage/sql/", "archive/", "src/macos-ui/", "src/sql/postgres/", "src/teller/")

    files: set[str] = set()
    for root, dirs, filenames in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in excluded_dirs and not any(d.startswith(prefix) for prefix in excluded_dir_prefixes)]
        for filename in filenames:
            path = Path(root) / filename
            if excluded_real and path.resolve() == excluded_real:
                continue
            rel = path.relative_to(repo_root).as_posix()
            if path.suffix.lower() in ALLOWED_SOURCE_EXTS:
                if rel in excluded_relative_paths:
                    continue
                if any(rel.startswith(prefix) for prefix in excluded_relative_prefixes):
                    continue
                files.add(rel)
    return sorted(files)
