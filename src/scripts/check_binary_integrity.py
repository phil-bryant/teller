#!/usr/bin/env python3
#R001: Collect executable path/version/hash metadata for configured binaries.
#R005: Evaluate required/min-version/hash policy and emit JSON/text reports.
#R010: Support strict exit gates for required-missing/version/hash failures.
"""Generate binary integrity reports for runtime and security toolchain commands."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from packaging.version import InvalidVersion, Version
except Exception:  # pragma: no cover - packaging may be unavailable
    InvalidVersion = ValueError
    Version = None


@dataclass(frozen=True)
class BinaryPolicy:
    identifier: str
    command: str
    required: bool
    version_args: tuple[str, ...]
    version_pattern: str
    min_version: str | None
    allowed_sha256: tuple[str, ...]


def _normalize_hex_digest(value: str) -> str:
    return value.strip().lower()


def _parse_binary_policy(entry: dict[str, Any], index: int) -> BinaryPolicy:
    identifier = str(entry.get("id") or entry.get("name") or f"binary-{index}").strip()
    command = str(entry.get("command", "")).strip()
    if not command:
        raise ValueError(f"Binary policy entry '{identifier}' is missing command.")
    version_args_raw = entry.get("version_args", ["--version"])
    if not isinstance(version_args_raw, list) or not all(isinstance(item, str) for item in version_args_raw):
        raise ValueError(f"Binary policy entry '{identifier}' has invalid version_args.")
    allowed_sha256_raw = entry.get("allowed_sha256", [])
    if not isinstance(allowed_sha256_raw, list) or not all(isinstance(item, str) for item in allowed_sha256_raw):
        raise ValueError(f"Binary policy entry '{identifier}' has invalid allowed_sha256 list.")
    min_version = entry.get("min_version")
    if min_version is not None:
        min_version = str(min_version).strip() or None
    return BinaryPolicy(
        identifier=identifier,
        command=command,
        required=bool(entry.get("required", False)),
        version_args=tuple(version_args_raw),
        version_pattern=str(entry.get("version_pattern", r"(\d+(?:\.\d+){0,3})")),
        min_version=min_version,
        allowed_sha256=tuple(_normalize_hex_digest(item) for item in allowed_sha256_raw if item.strip()),
    )


def load_policy(path: Path) -> list[BinaryPolicy]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    binaries = payload.get("binaries")
    if not isinstance(binaries, list):
        raise ValueError("Binary integrity policy must define a 'binaries' list.")
    parsed: list[BinaryPolicy] = []
    for idx, entry in enumerate(binaries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"Binary policy entry at index {idx} is not an object.")
        parsed.append(_parse_binary_policy(entry, idx))
    return parsed


def resolve_executable(command: str) -> str | None:
    if os.path.sep in command:
        path = Path(command).expanduser()
        if path.exists() and os.access(path, os.X_OK):
            return str(path.resolve())
        return None
    resolved = shutil.which(command)
    if not resolved:
        return None
    return str(Path(resolved).resolve())


def run_version_probe(executable_path: str, version_args: tuple[str, ...]) -> tuple[str | None, str | None]:
    cmd = [executable_path, *version_args]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        return None, "Version command timed out after 10s"
    except OSError as exc:
        return None, f"Version command failed to execute: {exc}"
    output = (result.stdout or "").strip()
    if not output:
        output = (result.stderr or "").strip()
    if result.returncode != 0:
        detail = output or f"exit {result.returncode}"
        return None, f"Version command returned non-zero ({detail})"
    return output or None, None


def parse_version(raw_output: str | None, pattern: str) -> str | None:
    if not raw_output:
        return None
    try:
        match = re.search(pattern, raw_output)
    except re.error:
        return None
    if not match:
        return None
    try:
        return match.group(1)
    except IndexError:
        return match.group(0)


def compare_versions(current: str, minimum: str) -> int | None:
    if Version is not None:
        try:
            current_version = Version(current)
            minimum_version = Version(minimum)
        except InvalidVersion:
            return None
        if current_version < minimum_version:
            return -1
        if current_version > minimum_version:
            return 1
        return 0
    current_parts = [int(part) for part in re.findall(r"\d+", current)]
    minimum_parts = [int(part) for part in re.findall(r"\d+", minimum)]
    if not current_parts or not minimum_parts:
        return None
    while len(current_parts) < len(minimum_parts):
        current_parts.append(0)
    while len(minimum_parts) < len(current_parts):
        minimum_parts.append(0)
    if current_parts < minimum_parts:
        return -1
    if current_parts > minimum_parts:
        return 1
    return 0


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def evaluate_binary(policy: BinaryPolicy) -> dict[str, Any]:
    executable_path = resolve_executable(policy.command)
    if executable_path is None:
        return {
            "id": policy.identifier,
            "command": policy.command,
            "required": policy.required,
            "status": "missing" if policy.required else "missing_optional",
            "path": None,
            "version_raw": None,
            "version": None,
            "version_probe_error": None,
            "minimum_version": policy.min_version,
            "version_status": "missing",
            "sha256": None,
            "hash_status": "missing",
        }

    raw_version, version_error = run_version_probe(executable_path, policy.version_args)
    parsed_version = parse_version(raw_version, policy.version_pattern)
    version_status = "ok"
    if policy.min_version:
        if parsed_version is None:
            version_status = "unknown"
        else:
            comparison = compare_versions(parsed_version, policy.min_version)
            if comparison is None:
                version_status = "unknown"
            elif comparison < 0:
                version_status = "stale"
            else:
                version_status = "ok"
    else:
        version_status = "not-configured"

    digest = sha256_file(executable_path)
    #R015: Enforce optional SHA256 allowlists for pinned high-sensitivity binaries.
    hash_status = "not-configured"
    if policy.allowed_sha256:
        hash_status = "ok" if _normalize_hex_digest(digest) in policy.allowed_sha256 else "mismatch"

    status = "ok"
    if hash_status == "mismatch":
        status = "hash_mismatch"
    elif version_status == "stale":
        status = "version_stale"
    elif version_status == "unknown" and policy.min_version:
        status = "unknown_version_parse"

    return {
        "id": policy.identifier,
        "command": policy.command,
        "required": policy.required,
        "status": status,
        "path": executable_path,
        "version_raw": raw_version,
        "version": parsed_version,
        "version_probe_error": version_error,
        "minimum_version": policy.min_version,
        "version_status": version_status,
        "sha256": digest,
        "hash_status": hash_status,
    }


def build_summary(entries: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "total": len(entries),
        "missing_required": 0,
        "missing_optional": 0,
        "version_stale": 0,
        "unknown_version_parse": 0,
        "hash_mismatch": 0,
        "ok": 0,
    }
    for entry in entries:
        status = entry["status"]
        if status == "missing":
            summary["missing_required"] += 1
        elif status == "missing_optional":
            summary["missing_optional"] += 1
        elif status == "version_stale":
            summary["version_stale"] += 1
        elif status == "unknown_version_parse":
            summary["unknown_version_parse"] += 1
        elif status == "hash_mismatch":
            summary["hash_mismatch"] += 1
        elif status == "ok":
            summary["ok"] += 1
    return summary


def make_report(policy_path: Path) -> dict[str, Any]:
    policies = load_policy(policy_path)
    entries = [evaluate_binary(policy) for policy in policies]
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "policy_file": str(policy_path),
        "summary": build_summary(entries),
        "binaries": entries,
    }


def format_report_text(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "Binary integrity report",
        f"- Total checks: {summary['total']}",
        f"- OK: {summary['ok']}",
        f"- Missing required: {summary['missing_required']}",
        f"- Missing optional: {summary['missing_optional']}",
        f"- Version stale: {summary['version_stale']}",
        f"- Version parse unknown: {summary['unknown_version_parse']}",
        f"- Hash mismatches: {summary['hash_mismatch']}",
        "",
        "Binary results:",
    ]
    for entry in report["binaries"]:
        lines.append(
            f"- {entry['id']}: {entry['status']} "
            f"(version={entry.get('version') or 'unknown'}; "
            f"min={entry.get('minimum_version') or 'not-configured'}; "
            f"hash={entry.get('hash_status')})"
        )
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate binary integrity reports.")
    parser.add_argument(
        "--policy",
        default="config/security/binary-integrity-policy.json",
        help="Path to binary integrity policy JSON.",
    )
    parser.add_argument(
        "--output-json",
        default="artifacts/security/binary-integrity.json",
        help="Path for JSON report output.",
    )
    parser.add_argument(
        "--output-text",
        default="artifacts/security/binary-integrity.txt",
        help="Path for text report output.",
    )
    parser.add_argument(
        "--fail-on-missing-required",
        action="store_true",
        help="Exit non-zero when required binaries are missing.",
    )
    parser.add_argument(
        "--fail-on-version",
        action="store_true",
        help="Exit non-zero on stale or unknown version parses for constrained binaries.",
    )
    parser.add_argument(
        "--fail-on-hash",
        action="store_true",
        help="Exit non-zero when binaries fail sha256 allowlist checks.",
    )
    return parser.parse_args()


def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    args = parse_args()
    policy_path = Path(args.policy)
    if not policy_path.exists():
        print(f"Binary integrity policy does not exist: {policy_path}", file=sys.stderr)
        return 2

    output_json = Path(args.output_json)
    output_text = Path(args.output_text)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_text.parent.mkdir(parents=True, exist_ok=True)

    try:
        report = make_report(policy_path)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"Failed to collect binary integrity data: {exc}", file=sys.stderr)
        return 2

    output_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text_report = format_report_text(report)
    output_text.write_text(text_report, encoding="utf-8")
    print(text_report, end="")

    summary = report["summary"]
    if args.fail_on_missing_required and summary["missing_required"] > 0:
        return 1
    if args.fail_on_version and (summary["version_stale"] > 0 or summary["unknown_version_parse"] > 0):
        return 1
    if args.fail_on_hash and summary["hash_mismatch"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
