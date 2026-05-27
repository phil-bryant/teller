from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .discovery import (
    discover_test_files_for_requirements,
    extract_source_files_from_analogous_tree,
    extract_source_files_from_requirements_path,
    list_repository_software_files,
    list_requirements_files,
)
from .parsing import (
    extract_numbered_requirement_test_ids,
    extract_numbered_test_ids,
    extract_requirement_ids,
    extract_scoped_source_ids,
    extract_source_ids,
    extract_ui_required_ids,
    format_bulleted,
    verify_requirements_numbered_test_bullets,
    detect_header_bundle_tags,
)


@dataclass
class TraceabilityVerifier:
    repo_root: Path

    def run(self, argv: list[str]) -> int:
        if argv and argv[0] in {"-h", "--help"}:
            print_usage()
            return 0
        if not argv:
            return 0 if self.verify_all_requirements() else 1
        if len(argv) == 2:
            requirements_file = self._to_repo_path(argv[0])
            source_file = self._to_repo_path(argv[1])
            return 0 if self.verify_single_pair_with_tests(requirements_file, source_file) else 1
        print_usage()
        return 1

    def verify_all_requirements(self) -> bool:
        requirements_files = list_requirements_files(self.repo_root)
        if not requirements_files:
            print("❌ FAIL: no requirements files found under requirements/**/*-requirements.md")
            return False
        print("Traceability check for all requirements/**/*-requirements.md")
        total = 0
        passed = 0
        failed = 0
        enforceable_count = 0
        for requirements_file in requirements_files:
            total += 1
            if not self.is_requirements_only_mode(requirements_file):
                enforceable_count += 1
            if self.verify_requirements_file_sources(requirements_file):
                passed += 1
            else:
                failed += 1
        print("")
        if enforceable_count == 0:
            print("✅ PASS: all requirements docs are requirements-only; global coverage checks skipped.")
        else:
            if not self.verify_numbered_script_requirements_coverage():
                failed += 1
            if not self.verify_numbered_requirement_scope_alignment():
                failed += 1
            if not self.verify_numbered_script_test_coverage():
                failed += 1
            if not self.verify_repository_source_requirements_coverage():
                failed += 1
        print("")
        print(f"Summary: total={total} pass={passed} fail={failed}")
        if failed == 0:
            print("✅ All traceability checks passed.")
            return True
        print("❌ One or more traceability checks failed.")
        return False

    def verify_single_pair_with_tests(self, requirements_file: Path, source_file: Path) -> bool:
        if self.is_requirements_only_mode(requirements_file):
            print(f"✅ PASS (requirements-only): {self._rel(requirements_file)} (source/test traceability skipped)")
            return True
        source_list = [self._rel(source_file)]
        default_tests, ui_tests = discover_test_files_for_requirements(requirements_file, source_list, self.repo_root)
        tests_inline = tests_inline_from_list(sorted(set(default_tests + ui_tests)))
        print("")
        print("Traceability check")
        print(f"- requirements: {self._rel(requirements_file)}")
        print(f"- source: {self._rel(source_file)}")
        print(f"- tests: {tests_inline}")
        if self.is_locked_source_file(source_file):
            return self.verify_single_pair(requirements_file, source_file, print_banner=False)

        status = True
        if not self.verify_single_pair(requirements_file, source_file, print_banner=False):
            status = False
        if not self.verify_requirements_test_traceability(requirements_file, source_list):
            status = False
        req_text = requirements_file.read_text(encoding="utf-8")
        issues = verify_requirements_numbered_test_bullets(req_text, self._rel(requirements_file))
        if issues:
            print("\n".join(issues))
            print(f"❌ FAIL (requirements-numbered-tests): {self._rel(requirements_file)} contains malformed test bullets.")
            status = False
        if not self.verify_numbered_test_traceability(requirements_file, source_list):
            status = False
        return status

    def verify_requirements_file_sources(self, requirements_file: Path) -> bool:
        if self.is_requirements_only_mode(requirements_file):
            print(f"✅ PASS (requirements-only): {self._rel(requirements_file)} (source/test traceability skipped)")
            return True

        source_list = extract_source_files_from_requirements_path(requirements_file)
        if not source_list:
            source_list = extract_source_files_from_analogous_tree(requirements_file, self.repo_root)
        if not source_list:
            print(f"❌ FAIL: {self._rel(requirements_file)} has no discoverable source file references.")
            return False

        found_source = False
        file_fail = False
        enforceable_source_list: list[str] = []
        for source in source_list:
            source_file = self._to_repo_path(source)
            found_source = True
            if not source_file.is_file():
                print(
                    f"❌ FAIL: {self._rel(requirements_file)} references missing source file {self._rel(source_file)}"
                )
                file_fail = True
                continue
            if not self.is_locked_source_file(source_file):
                enforceable_source_list.append(self._rel(source_file))
            default_tests, ui_tests = discover_test_files_for_requirements(
                requirements_file, [self._rel(source_file)], self.repo_root
            )
            tests_inline = tests_inline_from_list(sorted(set(default_tests + ui_tests)))
            print("")
            print("Traceability check")
            print(f"- requirements: {self._rel(requirements_file)}")
            print(f"- source: {self._rel(source_file)}")
            print(f"- tests: {tests_inline}")
            if self.verify_single_pair(requirements_file, source_file, print_banner=False):
                print(f"✅ PASS: {self._rel(requirements_file)} -> {self._rel(source_file)}")
            else:
                print(f"❌ FAIL: {self._rel(requirements_file)} -> {self._rel(source_file)}")
                file_fail = True

        if enforceable_source_list:
            if not self.verify_requirements_test_traceability(requirements_file, enforceable_source_list):
                file_fail = True
            req_text = requirements_file.read_text(encoding="utf-8")
            issues = verify_requirements_numbered_test_bullets(req_text, self._rel(requirements_file))
            if issues:
                print("\n".join(issues))
                print(f"❌ FAIL (requirements-numbered-tests): {self._rel(requirements_file)} contains malformed test bullets.")
                file_fail = True
            if not self.verify_numbered_test_traceability(requirements_file, enforceable_source_list):
                file_fail = True
        else:
            print(f"✅ PASS (locked-source-test-skip): {self._rel(requirements_file)} (all mapped sources are policy-locked)")

        if not found_source:
            print(f"❌ FAIL: {self._rel(requirements_file)} has no source files to verify.")
            return False
        return not file_fail

    def verify_single_pair(self, requirements_file: Path, source_file: Path, print_banner: bool = True) -> bool:
        if print_banner:
            print("")
            print("Traceability check")
            print(f"- requirements: {self._rel(requirements_file)}")
            print(f"- source: {self._rel(source_file)}")
        if not requirements_file.is_file():
            print(f"❌ Requirements file not found: {self._rel(requirements_file)}")
            return False
        if not source_file.is_file():
            print(f"❌ Source file not found: {self._rel(source_file)}")
            return False
        if self.is_locked_source_file(source_file):
            return self.verify_locked_exception(requirements_file, source_file)

        source_text = source_file.read_text(encoding="utf-8")
        header_bundle_line = detect_header_bundle_tags(source_text)
        if header_bundle_line:
            print(f"❌ FAIL (anti-cheat): header-level bundled #R tags detected in {self._rel(source_file)}:")
            print(f"  - {header_bundle_line}")
            print("  - Use scoped comments like '#R020: behavior' above each implementation block.")
            return False
        if not self.verify_strict_pair(requirements_file, source_file):
            return False
        return self.verify_scoped_traceability_comments(requirements_file, source_file)

    def verify_strict_pair(self, requirements_file: Path, source_file: Path) -> bool:
        req_ids = set(extract_requirement_ids(requirements_file.read_text(encoding="utf-8")))
        source_ids = set(extract_source_ids(source_file.read_text(encoding="utf-8")))
        missing_ids = sorted(req_ids - source_ids)
        extra_ids = sorted(source_ids - req_ids)
        if not missing_ids and not extra_ids:
            return True
        if missing_ids:
            print("❌ Missing #R tags for requirement IDs:")
            print(format_bulleted(missing_ids))
        if extra_ids:
            print("⚠️  Extra #R tags in source not present in requirements:")
            print(format_bulleted(extra_ids))
        return False

    def verify_scoped_traceability_comments(self, requirements_file: Path, source_file: Path) -> bool:
        req_ids = set(extract_requirement_ids(requirements_file.read_text(encoding="utf-8")))
        scoped_source_ids = set(extract_scoped_source_ids(source_file.read_text(encoding="utf-8")))
        missing = sorted(req_ids - scoped_source_ids)
        if not missing:
            return True
        print("❌ Missing scoped #R comments (#Rxxx:) for requirement IDs:")
        print(format_bulleted(missing))
        return False

    def verify_requirements_test_traceability(self, requirements_file: Path, source_list: list[str]) -> bool:
        req_text = requirements_file.read_text(encoding="utf-8")
        req_ids = set(extract_requirement_ids(req_text))
        ui_req_ids = set(extract_ui_required_ids(req_text))
        default_tests, ui_tests = discover_test_files_for_requirements(requirements_file, source_list, self.repo_root)
        combined_tests = sorted(set(default_tests + ui_tests))
        tests_inline = tests_inline_from_list(combined_tests)

        default_test_ids = self.collect_ids_from_test_list(default_tests)
        ui_test_ids = self.collect_ids_from_test_list(ui_tests)
        missing: list[str] = []
        for req_id in sorted(req_ids):
            if req_id in ui_req_ids:
                if req_id not in ui_test_ids:
                    missing.append(req_id)
                continue
            if req_id in default_test_ids or req_id in ui_test_ids:
                continue
            missing.append(req_id)

        if not missing:
            print(f"✅ PASS (test-traceability): {self._rel(requirements_file)} -> {tests_inline}")
            return True
        print(f"❌ FAIL (test-traceability): missing tagged tests for requirement IDs in {self._rel(requirements_file)}:")
        print(format_bulleted(missing))
        return False

    def verify_numbered_test_traceability(self, requirements_file: Path, source_list: list[str]) -> bool:
        if self._env_flag_false("STRICT_TRACEABILITY_NUMBERED_TAGS"):
            print(
                f"ℹ️  Numbered test-tag enforcement skipped for {self._rel(requirements_file)} (set STRICT_TRACEABILITY_NUMBERED_TAGS=true to re-enable)."
            )
            return True

        req_text = requirements_file.read_text(encoding="utf-8")
        req_ids = set(extract_requirement_ids(req_text))
        req_numbered_test_ids = set(extract_numbered_requirement_test_ids(req_text))
        default_tests, ui_tests = discover_test_files_for_requirements(requirements_file, source_list, self.repo_root)
        combined_tests = sorted(set(default_tests + ui_tests))

        collected_ids, misplaced = self.collect_numbered_test_ids_from_list(combined_tests)
        if misplaced:
            print("❌ FAIL (numbered-test-tag-placement): numbered #Rxxx-T## tags must be inside executable test blocks:")
            print(format_bulleted(sorted(set(misplaced))))
            print("  - Move numbered tags into @test/def test*/func test* bodies.")
            return False

        missing_req_testcase_ids = sorted(
            req_id for req_id in req_ids if not any(item.startswith(f"{req_id}-T") for item in req_numbered_test_ids)
        )
        if missing_req_testcase_ids:
            print(
                f"❌ FAIL (numbered-test-tags): missing Rxxx-T## entries in {self._rel(requirements_file)} for requirement IDs:"
            )
            print(format_bulleted(missing_req_testcase_ids))
            return False

        scoped_test_ids = sorted(item for item in collected_ids if item.split("-T", 1)[0] in req_ids)
        missing = sorted(req_numbered_test_ids - set(scoped_test_ids))
        extra = sorted(set(scoped_test_ids) - req_numbered_test_ids)
        if not missing and not extra:
            print(f"✅ PASS (numbered-test-tags): {self._rel(requirements_file)}")
            return True
        print(
            f"❌ FAIL (numbered-test-tags): requirements/tests #Rxxx-T## are not 1:1 for {self._rel(requirements_file)}:"
        )
        if missing:
            print("  Missing in tests (present in requirements):")
            print(format_bulleted(missing, prefix="    - "))
        if extra:
            print("  Missing in requirements (present in tests):")
            print(format_bulleted(extra, prefix="    - "))
        return False

    def verify_numbered_script_requirements_coverage(self) -> bool:
        script_pairs = []
        req_pairs = []
        for pattern in ("tests/[0-9][0-9]_*.sh", "tests/[0-9][0-9]_*.py", "[0-9][0-9]_*.sh", "[0-9][0-9]_*.py"):
            for script_file in self.repo_root.glob(pattern):
                num = script_file.name.split("_", 1)[0]
                script_pairs.append((num, self._rel(script_file)))
        for req_file in self.repo_root.glob("requirements/[0-9][0-9]_*-requirements.md"):
            num = req_file.name.split("_", 1)[0]
            req_pairs.append((num, self._rel(req_file)))
        req_nums = {num for num, _ in req_pairs}
        missing = [script_file for num, script_file in sorted(set(script_pairs)) if num not in req_nums]
        if not missing:
            print("✅ PASS: numbered script coverage complete (every numbered script has a numbered requirements doc).")
            return True
        print("❌ FAIL: missing numbered requirements docs for numbered scripts:")
        print(format_bulleted(f"{item} (expected requirements/{Path(item).name.split('_', 1)[0]}_*-requirements.md)" for item in missing))
        return False

    def verify_numbered_requirement_scope_alignment(self) -> bool:
        failures: list[str] = []
        for req_file in self.repo_root.glob("requirements/[0-9][0-9]_*-requirements.md"):
            req_num = req_file.name.split("_", 1)[0]
            source_list = extract_source_files_from_requirements_path(req_file)
            found_numbered = False
            matched = False
            for source_file in source_list:
                source_name = Path(source_file).name
                if (
                    source_file.startswith("tests/")
                    and source_name[:2].isdigit()
                    and "_" in source_name
                ) or (source_name[:2].isdigit() and "_" in source_name):
                    found_numbered = True
                    if source_name.split("_", 1)[0] == req_num:
                        matched = True
                if source_file.startswith("tests/t") and source_name[1:3].isdigit() and "_" in source_name:
                    found_numbered = True
                    matched = True
            if not found_numbered or not matched:
                failures.append(f"{self._rel(req_file)} must reference a numbered source starting with {req_num}_")
        if not failures:
            print("✅ PASS: numbered requirements scope alignment complete (NN requirements map to NN scripts).")
            return True
        print("❌ FAIL: numbered requirements scope mismatch:")
        print(format_bulleted(failures))
        return False

    def verify_numbered_script_test_coverage(self) -> bool:
        if self._env_flag_false("STRICT_TRACEABILITY_FULL_COVERAGE"):
            print(
                "ℹ️  Numbered script test-coverage check skipped (set STRICT_TRACEABILITY_FULL_COVERAGE=true to re-enable)."
            )
            return True
        missing = []
        for pattern in ("tests/[0-9][0-9]_*.sh", "tests/[0-9][0-9]_*.py", "[0-9][0-9]_*.sh", "[0-9][0-9]_*.py"):
            for script_file in self.repo_root.glob(pattern):
                stem = script_file.stem
                if not (self.repo_root / f"tests/sh/{stem}.bats").is_file():
                    missing.append(f"{self._rel(script_file)} (expected tests/sh/{stem}.bats)")
        if not missing:
            print("✅ PASS: numbered script test coverage complete (every numbered script has tests/sh/NN_*.bats).")
            return True
        print("❌ FAIL: numbered scripts missing companion shell tests:")
        print(format_bulleted(sorted(set(missing))))
        return False

    def verify_repository_source_requirements_coverage(self) -> bool:
        if self._env_flag_false("STRICT_TRACEABILITY_FULL_COVERAGE"):
            print(
                "ℹ️  Repository software coverage check skipped (set STRICT_TRACEABILITY_FULL_COVERAGE=true to re-enable)."
            )
            return True
        import os

        excluded_path = Path(__file__)
        wrapper_path = os.environ.get("TRACEABILITY_EXCLUDE_SOURCE")
        if wrapper_path:
            candidate = Path(wrapper_path)
            if not candidate.is_absolute():
                candidate = self.repo_root / candidate
            excluded_path = candidate
        all_sources = set(list_repository_software_files(self.repo_root, excluded_path=excluded_path))
        covered_sources: set[str] = set()
        for req_file in list_requirements_files(self.repo_root):
            if self.is_requirements_only_mode(req_file):
                continue
            source_list = extract_source_files_from_requirements_path(req_file)
            if not source_list:
                source_list = extract_source_files_from_analogous_tree(req_file, self.repo_root)
            for source_file in source_list:
                source_path = self._to_repo_path(source_file)
                if source_path.is_file():
                    covered_sources.add(self._rel(source_path))
        uncovered = sorted(all_sources - covered_sources)
        if not uncovered:
            print("✅ PASS: repository software files are covered by requirements docs.")
            return True
        print("❌ FAIL: repository software files missing requirements coverage:")
        print(format_bulleted(uncovered))
        return False

    def collect_ids_from_test_list(self, test_files: list[str]) -> set[str]:
        ids: set[str] = set()
        for test_file in test_files:
            path = self._to_repo_path(test_file)
            if path.is_file():
                ids.update(extract_source_ids(path.read_text(encoding="utf-8")))
        return ids

    def collect_numbered_test_ids_from_list(self, test_files: list[str]) -> tuple[set[str], list[str]]:
        ids: set[str] = set()
        misplaced: list[str] = []
        for test_file in test_files:
            path = self._to_repo_path(test_file)
            if not path.is_file():
                continue
            file_ids, file_misplaced = extract_numbered_test_ids(path)
            ids.update(file_ids)
            misplaced.extend(file_misplaced)
        return ids, misplaced

    def is_locked_source_file(self, source_file: Path) -> bool:
        text = source_file.read_text(encoding="utf-8")
        a = any(line.strip() == "## <AI_MODEL_INSTRUCTION>" for line in text.splitlines())
        b = any(line.strip() == "## DO_NOT_MODIFY_THIS_FILE" for line in text.splitlines())
        return a and b

    def is_requirements_only_mode(self, requirements_file: Path) -> bool:
        in_scope = False
        for line in requirements_file.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped == "## Scope":
                in_scope = True
                continue
            if stripped.startswith("## ") and in_scope:
                in_scope = False
            if in_scope and stripped.lower().startswith("requirements-only mode: true"):
                return True
            if stripped.startswith("R") and in_scope:
                in_scope = False
        return False

    def verify_locked_exception(self, requirements_file: Path, source_file: Path) -> bool:
        source_text = source_file.read_text(encoding="utf-8")
        if "<AI_MODEL_INSTRUCTION>" not in source_text or "DO_NOT_MODIFY_THIS_FILE" not in source_text:
            print(f"❌ FAIL (locked-policy): {self._rel(source_file)} is missing expected lock markers.")
            return False
        req_text = requirements_file.read_text(encoding="utf-8")
        has_policy_req = False
        for line in req_text.splitlines():
            lowered = line.lower()
            if lowered.startswith("r") and "statement:" in lowered and "locked" in lowered and "traceability" in lowered:
                has_policy_req = True
                break
        if not has_policy_req:
            print(f"❌ FAIL (locked-policy): {self._rel(requirements_file)} is missing locked-traceability policy requirement.")
            return False
        print(f"✅ PASS (locked-policy): {self._rel(source_file)} verified-with-exception.")
        return True

    def _to_repo_path(self, path: str | Path) -> Path:
        p = Path(path)
        if p.is_absolute():
            return p
        return self.repo_root / p

    def _rel(self, path: Path) -> str:
        try:
            return path.resolve().relative_to(self.repo_root.resolve()).as_posix()
        except ValueError:
            return str(path)

    @staticmethod
    def _env_flag_false(name: str) -> bool:
        import os

        return os.environ.get(name, "true").lower() == "false"


def tests_inline_from_list(test_files: list[str]) -> str:
    if not test_files:
        return "(none discovered)"
    return ", ".join(test_files)


def print_usage() -> None:
    print("Usage:")
    print("  ./tests/t04_run_requirements_traceability_tests.sh")
    print("  ./tests/t04_run_requirements_traceability_tests.sh <requirements_file> <source_file>")
    print("")
    print("Checks:")
    print("  - Requirements IDs <-> source #R tags (strict)")
    print("  - Requirement IDs -> discovered test #R tags (at least one per requirement)")
