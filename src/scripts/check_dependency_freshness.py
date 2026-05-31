#!/usr/bin/env python3
#R001: Parse requirements pins and classify outdated dependency update types.
#R005: Emit JSON/text freshness reports with direct/transitive metadata.
#R010: Enforce optional actionable/major/direct-outdated/venv-cruft failure gates.
"""Generate dependency freshness reports for direct and transitive packages."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from importlib import metadata as importlib_metadata
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from packaging.requirements import Requirement
    from packaging.specifiers import SpecifierSet
    from packaging.utils import canonicalize_name
    from packaging.version import InvalidVersion, Version
except Exception:  # pragma: no cover - fallback if packaging is unavailable
    Requirement = None
    SpecifierSet = None
    canonicalize_name = None
    InvalidVersion = ValueError
    Version = None


UPDATE_ORDER = {"major": 0, "minor": 1, "patch": 2, "unknown": 3}


@dataclass(frozen=True)
class RequirementSpec:
    name: str
    pinned_version: str | None
    is_exact_pin: bool


def normalize_package_name(name: str) -> str:
    normalized = re.sub(r"[-_.]+", "-", name).lower()
    if canonicalize_name is not None:
        return canonicalize_name(normalized)
    return normalized


def parse_requirements(requirements_path: Path) -> dict[str, RequirementSpec]:
    specs: dict[str, RequirementSpec] = {}
    for raw_line in requirements_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("-"):
            continue
        line = line.split("#", 1)[0].strip()
        if not line:
            continue

        match = re.match(r"^([A-Za-z0-9_.-]+)\s*(==\s*([^;\s]+))?", line)
        if not match:
            continue
        package_name = match.group(1)
        pinned_version = match.group(3)
        spec = RequirementSpec(
            name=package_name,
            pinned_version=pinned_version,
            is_exact_pin=bool(pinned_version),
        )
        specs[normalize_package_name(package_name)] = spec
    return specs


def parse_version_triplet(value: str) -> tuple[int, int, int] | None:
    if Version is not None:
        try:
            version = Version(value)
            release = list(version.release)
            while len(release) < 3:
                release.append(0)
            return release[0], release[1], release[2]
        except InvalidVersion:
            return None

    parts = re.findall(r"\d+", value)
    if not parts:
        return None
    while len(parts) < 3:
        parts.append("0")
    return int(parts[0]), int(parts[1]), int(parts[2])


def classify_update(current_version: str, latest_version: str) -> str:
    current = parse_version_triplet(current_version)
    latest = parse_version_triplet(latest_version)
    if current is None or latest is None:
        return "unknown"

    if latest[0] > current[0]:
        return "major"
    if latest[1] > current[1]:
        return "minor"
    if latest[2] > current[2]:
        return "patch"
    return "unknown"


def run_outdated_list() -> list[dict[str, Any]]:
    cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        stderr = result.stderr.strip() or "pip list failed without stderr"
        raise RuntimeError(stderr)
    try:
        parsed = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Could not parse pip output: {exc}") from exc
    if not isinstance(parsed, list):
        raise RuntimeError("Unexpected pip output format for outdated package list")
    return [item for item in parsed if isinstance(item, dict)]


def _collect_reverse_dependency_constraints() -> dict[str, list[dict[str, str]]]:
    reverse_constraints: dict[str, list[dict[str, str]]] = {}
    for dist in importlib_metadata.distributions():
        parent_raw = dist.metadata.get("Name")
        if not parent_raw:
            continue
        parent = normalize_package_name(parent_raw)
        for raw_requirement in dist.requires or []:
            requirement_text = str(raw_requirement).strip()
            if not requirement_text:
                continue
            if Requirement is None:
                requirement_name = requirement_text.split(";", 1)[0].strip().split(" ", 1)[0].split("[", 1)[0]
                if not requirement_name:
                    continue
                child = normalize_package_name(requirement_name)
                reverse_constraints.setdefault(child, []).append(
                    {
                        "parent": parent,
                        "specifier": "",
                        "requirement": requirement_text,
                    }
                )
                continue
            try:
                requirement = Requirement(requirement_text)
            except Exception:
                continue
            if requirement.marker is not None and not requirement.marker.evaluate():
                continue
            child = normalize_package_name(requirement.name)
            reverse_constraints.setdefault(child, []).append(
                {
                    "parent": parent,
                    "specifier": str(requirement.specifier),
                    "requirement": requirement_text,
                }
            )
    return reverse_constraints


def _collect_requested_packages() -> tuple[set[str], str]:
    cmd = [sys.executable, "-m", "pip", "inspect", "--local"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return set(), "unknown"
    try:
        payload = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        return set(), "unknown"
    installed = payload.get("installed")
    if not isinstance(installed, list):
        return set(), "unknown"
    requested: set[str] = set()
    for item in installed:
        if not isinstance(item, dict):
            continue
        if not item.get("requested", False):
            continue
        metadata = item.get("metadata", {})
        if not isinstance(metadata, dict):
            continue
        name = metadata.get("name")
        if not isinstance(name, str) or not name.strip():
            continue
        requested.add(normalize_package_name(name))
    return requested, "ok"


def _detect_venv_cruft(requirements: dict[str, RequirementSpec]) -> tuple[list[str], str]:
    requested, status = _collect_requested_packages()
    if status != "ok":
        return [], "unknown"
    allowlist = {"pip", "setuptools", "wheel"}
    declared = set(requirements.keys())
    cruft = sorted(requested - declared - allowlist)
    return cruft, "ok"


def _evaluate_actionability(latest_version: str, required_by: list[dict[str, str]]) -> tuple[str, bool | None]:
    if not required_by:
        return "actionable", True
    if Version is None or SpecifierSet is None:
        return "unknown", None
    try:
        latest = Version(latest_version)
    except InvalidVersion:
        return "unknown", None
    for edge in required_by:
        specifier = edge.get("specifier", "").strip()
        if not specifier:
            continue
        try:
            constraint = SpecifierSet(specifier)
        except Exception:
            return "unknown", None
        if latest not in constraint:
            return "constrained", False
    return "actionable", True


def _package_entry_from_outdated_row(
    row: dict[str, Any],
    requirements: dict[str, RequirementSpec],
    reverse_constraints: dict[str, list[dict[str, str]]],
) -> dict[str, Any] | None:
    name = str(row.get("name", "")).strip()
    current_version = str(row.get("version", "")).strip()
    latest_version = str(row.get("latest_version", "")).strip()
    if not name or not current_version or not latest_version:
        return None
    normalized = normalize_package_name(name)
    req_spec = requirements.get(normalized)
    update_type = classify_update(current_version, latest_version)
    required_by = sorted(
        reverse_constraints.get(normalized, []),
        key=lambda edge: (edge.get("parent", ""), edge.get("specifier", "")),
    )
    actionability, latest_satisfies_parent_constraints = _evaluate_actionability(latest_version, required_by)
    return {
        "name": name,
        "current_version": current_version,
        "latest_version": latest_version,
        "update_type": update_type,
        "in_requirements_txt": bool(req_spec),
        "is_exact_pin_in_requirements": bool(req_spec and req_spec.is_exact_pin),
        "requirements_pin_version": req_spec.pinned_version if req_spec else None,
        "required_by": required_by,
        "outdated_actionability": actionability,
        "latest_satisfies_parent_constraints": latest_satisfies_parent_constraints,
    }


def _build_summary(packages: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "total_outdated": len(packages),
        "major_updates": 0,
        "minor_updates": 0,
        "patch_updates": 0,
        "unknown_updates": 0,
        "direct_requirements_outdated": 0,
        "actionable_outdated": 0,
        "constrained_outdated": 0,
        "unknown_actionability_outdated": 0,
    }
    for item in packages:
        update_type = item["update_type"]
        if update_type == "major":
            summary["major_updates"] += 1
        elif update_type == "minor":
            summary["minor_updates"] += 1
        elif update_type == "patch":
            summary["patch_updates"] += 1
        else:
            summary["unknown_updates"] += 1
        if item["in_requirements_txt"]:
            summary["direct_requirements_outdated"] += 1
        actionability = item.get("outdated_actionability")
        if actionability == "actionable":
            summary["actionable_outdated"] += 1
        elif actionability == "constrained":
            summary["constrained_outdated"] += 1
        else:
            summary["unknown_actionability_outdated"] += 1
    return summary


def make_report(requirements_path: Path) -> dict[str, Any]:
    requirements = parse_requirements(requirements_path)
    outdated_rows = run_outdated_list()
    reverse_constraints = _collect_reverse_dependency_constraints()
    venv_cruft_packages, venv_cruft_status = _detect_venv_cruft(requirements)

    packages: list[dict[str, Any]] = []
    for row in outdated_rows:
        item = _package_entry_from_outdated_row(row, requirements, reverse_constraints)
        if item is not None:
            packages.append(item)

    packages.sort(key=lambda item: (UPDATE_ORDER.get(item["update_type"], 99), item["name"].lower()))

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "requirements_file": str(requirements_path),
        "summary": _build_summary(packages),
        "packages": packages,
        "venv_cruft_packages": venv_cruft_packages,
        "venv_cruft_status": venv_cruft_status,
    }


def format_report_text(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "Dependency freshness report",
        f"- Total outdated: {summary['total_outdated']}",
        f"- Major updates: {summary['major_updates']}",
        f"- Minor updates: {summary['minor_updates']}",
        f"- Patch updates: {summary['patch_updates']}",
        f"- Unknown updates: {summary['unknown_updates']}",
        f"- Outdated entries from requirements.txt: {summary['direct_requirements_outdated']}",
        f"- Actionable outdated entries: {summary['actionable_outdated']}",
        f"- Constrained outdated entries: {summary['constrained_outdated']}",
        f"- Unknown-actionability outdated entries: {summary['unknown_actionability_outdated']}",
        f"- Venv cruft status: {report.get('venv_cruft_status', 'unknown')}",
        f"- Venv cruft packages: {len(report.get('venv_cruft_packages', []))}",
    ]
    lines.append("")

    packages = report["packages"]
    if not packages:
        lines.append("No outdated packages found.")
        return "\n".join(lines) + "\n"

    lines.append("Outdated packages:")
    for item in packages:
        source = "requirements.txt" if item["in_requirements_txt"] else "transitive"
        pin_state = "pinned" if item["is_exact_pin_in_requirements"] else "not-pinned"
        actionability = item.get("outdated_actionability", "unknown")
        lines.append(
            f"- {item['name']}: {item['current_version']} -> {item['latest_version']} "
            f"({item['update_type']}; {source}; {pin_state}; {actionability})"
        )
    cruft_packages = report.get("venv_cruft_packages", [])
    if cruft_packages:
        lines.append("")
        lines.append("Venv cruft packages (requested but not declared in requirements.txt):")
        for package in cruft_packages:
            lines.append(f"- {package}")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Report outdated Python dependencies by update type.")
    parser.add_argument(
        "--requirements",
        default="requirements.txt",
        help="Path to requirements file (default: requirements.txt)",
    )
    parser.add_argument(
        "--output-json",
        default="artifacts/security/dependency-freshness.json",
        help="Path for JSON report output.",
    )
    parser.add_argument(
        "--output-text",
        default="artifacts/security/dependency-freshness.txt",
        help="Path for text summary output.",
    )
    parser.add_argument(
        "--fail-on-major",
        action="store_true",
        help="Exit non-zero when major updates are detected.",
    )
    parser.add_argument(
        "--fail-on-any-actionable-outdated",
        action="store_true",
        help="Exit non-zero when any actionable outdated package is detected.",
    )
    parser.add_argument(
        "--fail-on-direct-outdated",
        action="store_true",
        help="Exit non-zero when outdated packages are listed in requirements.txt.",
    )
    parser.add_argument(
        "--fail-on-venv-cruft",
        action="store_true",
        help="Exit non-zero when requested venv packages are not declared in requirements.txt.",
    )
    return parser.parse_args()


def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    args = parse_args()
    requirements_path = Path(args.requirements)
    if not requirements_path.exists():
        print(f"Requirements file does not exist: {requirements_path}", file=sys.stderr)
        return 2

    output_json = Path(args.output_json)
    output_text = Path(args.output_text)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_text.parent.mkdir(parents=True, exist_ok=True)

    try:
        report = make_report(requirements_path)
    except RuntimeError as exc:
        print(f"Failed to collect dependency freshness data: {exc}", file=sys.stderr)
        return 2

    output_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text_report = format_report_text(report)
    output_text.write_text(text_report, encoding="utf-8")
    print(text_report, end="")

    if args.fail_on_any_actionable_outdated and report["summary"]["actionable_outdated"] > 0:
        return 1
    if args.fail_on_major and report["summary"]["major_updates"] > 0:
        return 1
    if args.fail_on_direct_outdated and report["summary"]["direct_requirements_outdated"] > 0:
        return 1
    if args.fail_on_venv_cruft and len(report.get("venv_cruft_packages", [])) > 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
