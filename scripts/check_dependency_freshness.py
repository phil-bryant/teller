#!/usr/bin/env python3
"""Generate dependency freshness reports for direct and transitive packages."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from packaging.version import InvalidVersion, Version
except Exception:  # pragma: no cover - fallback if packaging is unavailable
    InvalidVersion = ValueError
    Version = None


UPDATE_ORDER = {"major": 0, "minor": 1, "patch": 2, "unknown": 3}


@dataclass(frozen=True)
class RequirementSpec:
    name: str
    pinned_version: str | None
    is_exact_pin: bool


def normalize_package_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


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


def make_report(requirements_path: Path) -> dict[str, Any]:
    requirements = parse_requirements(requirements_path)
    outdated_rows = run_outdated_list()

    packages: list[dict[str, Any]] = []
    for row in outdated_rows:
        name = str(row.get("name", "")).strip()
        current_version = str(row.get("version", "")).strip()
        latest_version = str(row.get("latest_version", "")).strip()
        if not name or not current_version or not latest_version:
            continue

        normalized = normalize_package_name(name)
        req_spec = requirements.get(normalized)
        update_type = classify_update(current_version, latest_version)
        packages.append(
            {
                "name": name,
                "current_version": current_version,
                "latest_version": latest_version,
                "update_type": update_type,
                "in_requirements_txt": bool(req_spec),
                "is_exact_pin_in_requirements": bool(req_spec and req_spec.is_exact_pin),
                "requirements_pin_version": req_spec.pinned_version if req_spec else None,
            }
        )

    packages.sort(key=lambda item: (UPDATE_ORDER.get(item["update_type"], 99), item["name"].lower()))

    summary = {
        "total_outdated": len(packages),
        "major_updates": sum(1 for item in packages if item["update_type"] == "major"),
        "minor_updates": sum(1 for item in packages if item["update_type"] == "minor"),
        "patch_updates": sum(1 for item in packages if item["update_type"] == "patch"),
        "unknown_updates": sum(1 for item in packages if item["update_type"] == "unknown"),
        "direct_requirements_outdated": sum(1 for item in packages if item["in_requirements_txt"]),
    }

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "requirements_file": str(requirements_path),
        "summary": summary,
        "packages": packages,
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
        "",
    ]

    packages = report["packages"]
    if not packages:
        lines.append("No outdated packages found.")
        return "\n".join(lines) + "\n"

    lines.append("Outdated packages:")
    for item in packages:
        source = "requirements.txt" if item["in_requirements_txt"] else "transitive"
        pin_state = "pinned" if item["is_exact_pin_in_requirements"] else "not-pinned"
        lines.append(
            f"- {item['name']}: {item['current_version']} -> {item['latest_version']} "
            f"({item['update_type']}; {source}; {pin_state})"
        )
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
        default=".security-reports/dependency-freshness.json",
        help="Path for JSON report output.",
    )
    parser.add_argument(
        "--output-text",
        default=".security-reports/dependency-freshness.txt",
        help="Path for text summary output.",
    )
    parser.add_argument(
        "--fail-on-major",
        action="store_true",
        help="Exit non-zero when major updates are detected.",
    )
    parser.add_argument(
        "--fail-on-direct-outdated",
        action="store_true",
        help="Exit non-zero when outdated packages are listed in requirements.txt.",
    )
    return parser.parse_args()


def main() -> int:
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

    if args.fail_on_major and report["summary"]["major_updates"] > 0:
        return 1
    if args.fail_on_direct_outdated and report["summary"]["direct_requirements_outdated"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
