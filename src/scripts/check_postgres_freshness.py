#!/usr/bin/env python3
#R020: Collect PostgreSQL client/server freshness data with policy-aware gating.
#R025: Evaluate CVE exposure using snapshot and policy inputs.
"""Generate PostgreSQL version freshness and CVE exposure reports."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shlex
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

try:
    import requests
except ModuleNotFoundError:  # pragma: no cover - dependency availability varies by runtime
    requests = None


SEVERITY_ORDER = {
    "low": 1,
    "medium": 2,
    "moderate": 2,
    "high": 3,
    "critical": 4,
}

POSTGRES_SECURITY_BASE_URL = "https://www.postgresql.org/support/security"
POSTGRES_SECURITY_HOST = "www.postgresql.org"
HTTP_USER_AGENT = "teller-postgres-cve-check/1.0"


def parse_semver(value: str | None) -> tuple[int, int, int] | None:
    if not value:
        return None
    parts = re.findall(r"\d+", value)
    if not parts:
        return None
    while len(parts) < 3:
        parts.append("0")
    return int(parts[0]), int(parts[1]), int(parts[2])


def compare_semver(left: str | None, right: str | None) -> int | None:
    left_triplet = parse_semver(left)
    right_triplet = parse_semver(right)
    if left_triplet is None or right_triplet is None:
        return None
    if left_triplet < right_triplet:
        return -1
    if left_triplet > right_triplet:
        return 1
    return 0


def parse_psql_client_version(raw_output: str) -> str | None:
    match = re.search(r"(\d+(?:\.\d+){0,2})", raw_output)
    return match.group(1) if match else None


def parse_server_version_num(raw_value: str) -> str | None:
    digits = re.sub(r"\D", "", raw_value)
    if not digits:
        return None
    version_num = int(digits)
    major = version_num // 10000
    if major >= 10:
        # PostgreSQL 10+ encodes server_version_num as major * 10000 + minor
        minor = version_num % 10000
        return f"{major}.{minor}.0"
    minor = (version_num % 10000) // 100
    patch = version_num % 100
    return f"{major}.{minor}.{patch}"


def meets_minimum(current: str | None, minimum: str | None) -> bool | None:
    if not minimum:
        return None
    current_triplet = parse_semver(current)
    minimum_triplet = parse_semver(minimum)
    if current_triplet is None or minimum_triplet is None:
        return None
    return current_triplet >= minimum_triplet


def normalize_severity(value: str | None) -> str:
    if not value:
        return "unknown"
    lowered = value.strip().lower()
    if lowered in SEVERITY_ORDER:
        return lowered
    return "unknown"


def severity_meets_threshold(value: str | None, threshold: str | None) -> bool:
    normalized = normalize_severity(value)
    normalized_threshold = normalize_severity(threshold)
    return SEVERITY_ORDER.get(normalized, 0) >= SEVERITY_ORDER.get(normalized_threshold, 0)


def parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def satisfies_constraint(version: str | None, constraint: str) -> bool:
    match = re.match(r"^\s*(<=|>=|<|>|==|=)\s*([0-9][0-9A-Za-z.\-]*)\s*$", constraint)
    if not match:
        return False
    operator = match.group(1)
    target_version = match.group(2)
    comparison = compare_semver(version, target_version)
    if comparison is None:
        return False
    if operator in {"=", "=="}:
        return comparison == 0
    if operator == ">":
        return comparison > 0
    if operator == ">=":
        return comparison >= 0
    if operator == "<":
        return comparison < 0
    if operator == "<=":
        return comparison <= 0
    return False


def satisfies_range(version: str | None, expression: str) -> bool:
    constraints = [part.strip() for part in expression.split(",") if part.strip()]
    if not constraints:
        return False
    return all(satisfies_constraint(version, constraint) for constraint in constraints)


def version_in_any_range(version: str | None, ranges: list[str]) -> bool:
    if not version:
        return False
    return any(satisfies_range(version, expression) for expression in ranges if expression)


def read_json_file(path_value: str | None) -> dict[str, Any] | None:
    if not path_value:
        return None
    path = Path(path_value)
    if not path.exists():
        return None
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return None
    return payload


def should_write_refreshed_snapshot(
    existing_snapshot: dict[str, Any] | None,
    refreshed_snapshot: dict[str, Any] | None,
) -> bool:
    if not isinstance(refreshed_snapshot, dict):
        return False
    if not isinstance(existing_snapshot, dict):
        return True
    existing_payload = {key: value for key, value in existing_snapshot.items() if key != "generated_at"}
    refreshed_payload = {key: value for key, value in refreshed_snapshot.items() if key != "generated_at"}
    return existing_payload != refreshed_payload


def component_to_scope(component_text: str) -> str:
    lowered = component_text.lower()
    if "client" in lowered:
        return "client"
    if "server" in lowered or "contrib module" in lowered:
        return "server"
    return "both"


def score_to_severity(cvss_score: float | None) -> str:
    if cvss_score is None:
        return "unknown"
    if cvss_score >= 9.0:
        return "critical"
    if cvss_score >= 7.0:
        return "high"
    if cvss_score >= 4.0:
        return "medium"
    return "low"


def strip_html(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", value))).strip()


def extract_major(version: str | None) -> str | None:
    parsed = parse_semver(version)
    if parsed is None:
        return None
    return str(parsed[0])


def validate_postgresql_major(major: str) -> str:
    trimmed = major.strip()
    if not re.fullmatch(r"[1-9][0-9]?", trimmed):
        raise ValueError(f"Invalid PostgreSQL major version for CVE fetch: {major!r}")
    return trimmed


def fetch_postgresql_security_page(major: str) -> str:
    if requests is None:
        raise RuntimeError("requests is required to refresh PostgreSQL CVE snapshots.")
    normalized_major = validate_postgresql_major(major)
    page_url = f"{POSTGRES_SECURITY_BASE_URL}/{normalized_major}/"
    try:
        response = requests.get(
            page_url,
            headers={"User-Agent": HTTP_USER_AGENT},
            timeout=20,
            allow_redirects=False,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        raise RuntimeError(f"Network error fetching {page_url}: {exc}") from exc

    resolved_url = str(getattr(response, "url", page_url))
    parsed = urlsplit(resolved_url)
    if parsed.scheme.lower() != "https" or parsed.netloc.lower() != POSTGRES_SECURITY_HOST:
        raise RuntimeError(f"Unexpected CVE source URL host/scheme: {resolved_url}")

    response.encoding = response.encoding or "utf-8"
    return response.text


def fetch_postgresql_cve_snapshot(majors: set[str]) -> dict[str, Any]:
    cves: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for major in sorted(majors):
        normalized_major = validate_postgresql_major(major)
        page_url = f"{POSTGRES_SECURITY_BASE_URL}/{normalized_major}/"
        html_text = fetch_postgresql_security_page(normalized_major)
        for row_match in re.finditer(r"<tr>(.*?)</tr>", html_text, flags=re.S | re.I):
            row_html = row_match.group(1)
            if "CVE-" not in row_html:
                continue
            cells = re.findall(r"<td[^>]*>(.*?)</td>", row_html, flags=re.S | re.I)
            if len(cells) < 5:
                continue
            reference_cell, _affected_cell, fixed_cell, component_cell, desc_cell = cells[:5]
            cve_match = re.search(r"CVE-\d{4}-\d+", reference_cell, flags=re.I)
            if not cve_match:
                continue
            cve_id = cve_match.group(0).upper()
            component_scope = component_to_scope(strip_html(component_cell))
            fixed_versions = re.findall(rf"\b{re.escape(normalized_major)}\.\d+\b", strip_html(fixed_cell))
            if not fixed_versions:
                continue
            fixed_version = fixed_versions[0]
            cvss_match = re.search(r">([0-9]+(?:\.[0-9]+)?)<", component_cell)
            cvss_value = float(cvss_match.group(1)) if cvss_match else None
            severity = score_to_severity(cvss_value)
            title = strip_html(desc_cell).split(" more details", 1)[0].strip()
            key = (cve_id, component_scope, fixed_version)
            if key in seen:
                continue
            seen.add(key)
            cves.append(
                {
                    "id": cve_id,
                    "severity": severity,
                    "title": title,
                    "source": page_url,
                    "affected": [
                        {
                            "component": component_scope,
                            "ranges": [f">={normalized_major}.0,<{fixed_version}"],
                            "fixed_versions": [fixed_version],
                        }
                    ],
                }
            )
    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": "postgresql.org/support/security/<major>/",
        "cves": cves,
    }


def _initial_cve_result(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "checked": args.check_cves,
        "policy_file": args.cve_policy or None,
        "snapshot_file": args.cve_snapshot or None,
        "snapshot_generated_at": None,
        "snapshot_age_hours": None,
        "snapshot_stale": None,
        "severity_threshold": "high",
        "fail_on_cve": args.fail_on_cve,
        "fail_on_stale_snapshot": False,
        "max_snapshot_age_hours": 168,
        "snapshot_cve_count": 0,
        "vulnerabilities": [],
        "warnings": [],
        "status": "not-checked",
        "assurance": "not-applicable",
        "gate_failed": False,
    }


def _load_cve_policy(args: argparse.Namespace) -> dict[str, Any]:
    policy = {
        "severity_threshold": "high",
        "max_snapshot_age_hours": 168,
        "fail_on_stale_snapshot": False,
    }
    policy_payload = read_json_file(args.cve_policy)
    if not policy_payload:
        return policy
    policy.update(
        {
            "severity_threshold": policy_payload.get("severity_threshold", policy["severity_threshold"]),
            "max_snapshot_age_hours": int(policy_payload.get("max_snapshot_age_hours", policy["max_snapshot_age_hours"])),
            "fail_on_stale_snapshot": bool(policy_payload.get("fail_on_stale_snapshot", policy["fail_on_stale_snapshot"])),
        }
    )
    return policy


def _refresh_or_load_snapshot(
    args: argparse.Namespace,
    client_version: str | None,
    server_version: str | None,
    result: dict[str, Any],
) -> dict[str, Any] | None:
    snapshot: dict[str, Any] | None = None
    if args.refresh_cve_snapshot:
        target_majors: set[str] = set()
        client_major = extract_major(client_version)
        server_major = extract_major(server_version)
        if client_major:
            target_majors.add(client_major)
        if server_major:
            target_majors.add(server_major)
        if not target_majors:
            target_majors = {"15"}
        try:
            snapshot = fetch_postgresql_cve_snapshot(target_majors)
            if args.cve_snapshot:
                snapshot_path = Path(args.cve_snapshot)
                snapshot_path.parent.mkdir(parents=True, exist_ok=True)
                existing_snapshot = read_json_file(args.cve_snapshot)
                if should_write_refreshed_snapshot(existing_snapshot, snapshot):
                    snapshot_path.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
        except Exception as exc:  # pragma: no cover - network can fail for many reasons
            result["warnings"].append(f"Failed to refresh CVE snapshot from postgresql.org: {exc}")
    if snapshot is not None:
        return snapshot
    return read_json_file(args.cve_snapshot)


def _mark_policy_failed(result: dict[str, Any]) -> None:
    result["gate_failed"] = True
    result["status"] = "failed"
    result["assurance"] = "policy-failed"


def _apply_snapshot_freshness(result: dict[str, Any], generated_at: datetime | None, args: argparse.Namespace) -> None:
    if generated_at is None:
        result["warnings"].append("CVE snapshot missing valid generated_at timestamp.")
        result["snapshot_stale"] = True
        result["status"] = "inconclusive"
        result["assurance"] = "invalid-snapshot-timestamp"
        if args.fail_on_cve and result["fail_on_stale_snapshot"]:
            _mark_policy_failed(result)
        return
    now = datetime.now(timezone.utc)
    age_hours = (now - generated_at).total_seconds() / 3600.0
    result["snapshot_generated_at"] = generated_at.isoformat().replace("+00:00", "Z")
    result["snapshot_age_hours"] = round(age_hours, 2)
    result["snapshot_stale"] = age_hours > float(result["max_snapshot_age_hours"])
    if result["snapshot_stale"]:
        result["warnings"].append("CVE snapshot is older than allowed freshness policy.")
        result["status"] = "inconclusive"
        result["assurance"] = "stale-snapshot"
        if args.fail_on_cve and result["fail_on_stale_snapshot"]:
            _mark_policy_failed(result)


def _collect_cve_findings(
    cve_entries: list[Any],
    threshold: str,
    client_version: str | None,
    server_version: str | None,
) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for cve in cve_entries:
        if not isinstance(cve, dict):
            continue
        cve_id = str(cve.get("id", "unknown"))
        severity = str(cve.get("severity", "unknown"))
        if not severity_meets_threshold(severity, threshold):
            continue
        affected_specs = cve.get("affected", [])
        if not isinstance(affected_specs, list):
            continue
        for spec in affected_specs:
            findings.extend(
                _findings_for_spec(
                    cve_id=cve_id,
                    severity=severity,
                    title=cve.get("title"),
                    spec=spec,
                    client_version=client_version,
                    server_version=server_version,
                )
            )
    return findings


def _findings_for_spec(
    *,
    cve_id: str,
    severity: str,
    title: Any,
    spec: Any,
    client_version: str | None,
    server_version: str | None,
) -> list[dict[str, Any]]:
    if not isinstance(spec, dict):
        return []
    component = str(spec.get("component", "both")).lower()
    ranges = spec.get("ranges", [])
    if isinstance(ranges, str):
        ranges = [ranges]
    if not isinstance(ranges, list):
        return []
    results: list[dict[str, Any]] = []
    if component in {"client", "both"} and version_in_any_range(client_version, ranges):
        results.append(
            {
                "id": cve_id,
                "severity": normalize_severity(severity),
                "component": "client",
                "installed_version": client_version,
                "matched_ranges": ranges,
                "fixed_versions": spec.get("fixed_versions", []),
                "title": title,
            }
        )
    if component in {"server", "both"} and version_in_any_range(server_version, ranges):
        results.append(
            {
                "id": cve_id,
                "severity": normalize_severity(severity),
                "component": "server",
                "installed_version": server_version,
                "matched_ranges": ranges,
                "fixed_versions": spec.get("fixed_versions", []),
                "title": title,
            }
        )
    return results


def _build_server_version_command(args: argparse.Namespace) -> list[str]:
    server_cmd = ["psql"]
    if args.server_psql_args:
        server_cmd.extend(shlex.split(args.server_psql_args))
    elif args.server_dsn:
        server_cmd.append(args.server_dsn)
    server_cmd.extend(["-tAc", "SHOW server_version_num;"])
    return server_cmd


def _check_client_version(
    *,
    args: argparse.Namespace,
    psql_path: str | None,
    client_info: dict[str, Any],
    warnings: list[str],
    stale_components: list[str],
) -> None:
    if not psql_path:
        warnings.append("psql not found on PATH; PostgreSQL freshness checks skipped.")
        if args.fail_on_stale:
            stale_components.append("client_missing")
            if args.check_server_version:
                stale_components.append("server_missing")
        return
    client_exit, client_output = run_command(["psql", "--version"])
    if client_exit != 0:
        client_info["status"] = "error"
        client_info["error"] = client_output or "psql --version failed"
        warnings.append("Could not determine psql client version.")
        if args.fail_on_stale:
            stale_components.append("client_unknown")
        return
    client_version = parse_psql_client_version(client_output)
    client_info["version"] = client_version
    client_min_check = meets_minimum(client_version, args.min_client_version)
    client_info["meets_minimum"] = client_min_check
    if client_version is None:
        client_info["status"] = "unknown"
        warnings.append("Could not parse psql client version output.")
        if args.fail_on_stale:
            stale_components.append("client_unknown")
    elif client_min_check is False:
        client_info["status"] = "stale"
        stale_components.append("client_outdated")
    else:
        client_info["status"] = "ok"


def _check_server_version(
    *,
    args: argparse.Namespace,
    psql_path: str | None,
    server_info: dict[str, Any],
    warnings: list[str],
    stale_components: list[str],
) -> None:
    if not args.check_server_version or not psql_path:
        return
    server_exit, server_output = run_command(_build_server_version_command(args))
    if server_exit != 0:
        server_info["status"] = "error"
        server_info["error"] = server_output or "SHOW server_version_num failed"
        warnings.append("Could not determine PostgreSQL server version " f"(attempted {describe_server_target(args)}).")
        if args.fail_on_stale:
            stale_components.append("server_unknown")
        return
    server_version = parse_server_version_num(server_output)
    server_info["version"] = server_version
    server_min_check = meets_minimum(server_version, args.min_server_version)
    server_info["meets_minimum"] = server_min_check
    if server_version is None:
        server_info["status"] = "unknown"
        warnings.append("Could not parse server_version_num.")
        if args.fail_on_stale:
            stale_components.append("server_unknown")
    elif server_min_check is False:
        server_info["status"] = "stale"
        stale_components.append("server_outdated")
    else:
        server_info["status"] = "ok"


def _validate_cve_entries(result: dict[str, Any], snapshot: dict[str, Any]) -> list[Any] | None:
    cve_entries = snapshot.get("cves", [])
    if not isinstance(cve_entries, list):
        result["warnings"].append("CVE snapshot 'cves' payload is not a list.")
        result["status"] = "inconclusive"
        result["assurance"] = "invalid-snapshot-format"
        return None
    result["snapshot_cve_count"] = len(cve_entries)
    if len(cve_entries) == 0:
        result["warnings"].append(
            "CVE snapshot contains zero entries; vulnerability evaluation is inconclusive."
        )
        result["status"] = "inconclusive"
        result["assurance"] = "empty-snapshot"
    return cve_entries


def _merge_cve_summary(
    *,
    cve_result: dict[str, Any],
    warnings: list[str],
    stale_components: list[str],
) -> None:
    if cve_result.get("warnings"):
        warnings.extend(cve_result["warnings"])
    if cve_result.get("vulnerabilities"):
        stale_components.append("cve_vulnerable")
    if cve_result.get("snapshot_stale"):
        stale_components.append("cve_snapshot_stale")
    if cve_result["checked"] and cve_result["gate_failed"] and not cve_result.get("vulnerabilities"):
        stale_components.append("cve_policy_unmet")


def _base_report_lines(report: dict[str, Any]) -> list[str]:
    client = report["client"]
    server = report["server"]
    cve = report["cve"]
    return [
        "PostgreSQL freshness report",
        f"- Client status: {client['status']}",
        f"- Client version: {client['version'] or 'unknown'}",
        f"- Client minimum: {client['minimum_version'] or 'not configured'}",
        f"- Server check enabled: {'yes' if server['checked'] else 'no'}",
        f"- Server status: {server['status']}",
        f"- Server version: {server['version'] or 'unknown'}",
        f"- Server minimum: {server['minimum_version'] or 'not configured'}",
        f"- CVE checks enabled: {'yes' if cve['checked'] else 'no'}",
        f"- CVE severity threshold: {cve['severity_threshold']}",
        f"- CVE snapshot entries: {cve['snapshot_cve_count']}",
        f"- CVE snapshot generated at: {cve['snapshot_generated_at'] or 'unknown'}",
        f"- CVE snapshot age hours: {cve['snapshot_age_hours'] if cve['snapshot_age_hours'] is not None else 'unknown'}",
        f"- CVE evaluation status: {cve['status']}",
        f"- CVE assurance: {cve['assurance']}",
        f"- CVE vulnerabilities found: {len(cve['vulnerabilities'])}",
    ]


def _initial_client_info(args: argparse.Namespace, psql_path: str | None) -> dict[str, Any]:
    status = "unknown"
    if not psql_path:
        status = "missing"
    return {
        "available": bool(psql_path),
        "version": None,
        "minimum_version": args.min_client_version or None,
        "meets_minimum": None,
        "status": status,
        "error": None,
    }


def _initial_server_info(args: argparse.Namespace, psql_path: str | None) -> dict[str, Any]:
    status = "unknown"
    if not args.check_server_version:
        status = "not-checked"
    return {
        "checked": args.check_server_version,
        "available": bool(psql_path),
        "version": None,
        "minimum_version": args.min_server_version or None,
        "meets_minimum": None,
        "status": status,
        "error": None,
    }


def _policy_from_args(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "min_client_version": args.min_client_version or None,
        "min_server_version": args.min_server_version or None,
        "check_server_version": args.check_server_version,
        "fail_on_stale": args.fail_on_stale,
        "check_cves": args.check_cves,
        "fail_on_cve": args.fail_on_cve,
        "cve_snapshot": args.cve_snapshot or None,
        "cve_policy": args.cve_policy or None,
    }


def evaluate_cves(
    *,
    args: argparse.Namespace,
    client_version: str | None,
    server_version: str | None,
) -> dict[str, Any]:
    result: dict[str, Any] = _initial_cve_result(args)
    if not args.check_cves:
        return result
    result["status"] = "evaluating"
    result["assurance"] = "unknown"

    policy = _load_cve_policy(args)
    result["severity_threshold"] = str(policy["severity_threshold"])
    result["max_snapshot_age_hours"] = int(policy["max_snapshot_age_hours"])
    result["fail_on_stale_snapshot"] = bool(policy["fail_on_stale_snapshot"])

    snapshot = _refresh_or_load_snapshot(args, client_version, server_version, result)
    if snapshot is None:
        result["warnings"].append("CVE snapshot is missing or invalid; skipping CVE evaluation.")
        result["status"] = "inconclusive"
        result["assurance"] = "no-snapshot"
        if args.fail_on_cve:
            _mark_policy_failed(result)
        return result

    generated_at = parse_iso_datetime(str(snapshot.get("generated_at", "")))
    _apply_snapshot_freshness(result, generated_at, args)

    cve_entries = _validate_cve_entries(result, snapshot)
    if cve_entries is None:
        return result

    threshold = result["severity_threshold"]
    findings = _collect_cve_findings(cve_entries, threshold, client_version, server_version)
    result["vulnerabilities"] = findings
    if findings:
        result["status"] = "failed" if args.fail_on_cve else "vulnerable"
        result["assurance"] = "known-vulnerable"
    elif result["status"] == "evaluating":
        result["status"] = "passed"
        result["assurance"] = "matched-against-snapshot"
    if args.fail_on_cve and findings:
        result["gate_failed"] = True
    return result


def run_command(args: list[str], timeout_seconds: int = 10) -> tuple[int, str]:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return 124, f"Command timed out after {timeout_seconds}s: {' '.join(args)}"
    output = (result.stdout or "").strip()
    if not output and result.stderr:
        output = result.stderr.strip()
    return result.returncode, output


def describe_server_target(args: argparse.Namespace) -> str:
    if args.server_psql_args:
        return f"psql args: {args.server_psql_args}"
    if args.server_dsn:
        return "server dsn"
    return "default psql args"


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    stale_components: list[str] = []
    warnings: list[str] = []
    psql_path = shutil.which("psql")

    client_info = _initial_client_info(args, psql_path)
    server_info = _initial_server_info(args, psql_path)

    _check_client_version(
        args=args,
        psql_path=psql_path,
        client_info=client_info,
        warnings=warnings,
        stale_components=stale_components,
    )
    _check_server_version(
        args=args,
        psql_path=psql_path,
        server_info=server_info,
        warnings=warnings,
        stale_components=stale_components,
    )

    cve_result = evaluate_cves(
        args=args,
        client_version=client_info["version"],
        server_version=server_info["version"],
    )
    _merge_cve_summary(cve_result=cve_result, warnings=warnings, stale_components=stale_components)

    gate_failed = bool((args.fail_on_stale and stale_components) or cve_result.get("gate_failed"))
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "policy": _policy_from_args(args),
        "client": client_info,
        "server": server_info,
        "cve": cve_result,
        "summary": {
            "stale_components": stale_components,
            "warnings": warnings,
            "gate_failed": gate_failed,
        },
    }


def format_text_report(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = _base_report_lines(report)
    if summary["warnings"]:
        lines.append("- Warnings:")
        for warning in summary["warnings"]:
            lines.append(f"  - {warning}")
    if summary["stale_components"]:
        lines.append(f"- Stale components: {', '.join(summary['stale_components'])}")
    else:
        lines.append("- Stale components: none")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate PostgreSQL version freshness reports.")
    parser.add_argument(
        "--output-json",
        default="artifacts/security/postgres-freshness.json",
        help="Path for JSON report output.",
    )
    parser.add_argument(
        "--output-text",
        default="artifacts/security/postgres-freshness.txt",
        help="Path for text report output.",
    )
    parser.add_argument(
        "--min-client-version",
        default="",
        help="Minimum acceptable psql client version (e.g. 16.0).",
    )
    parser.add_argument(
        "--min-server-version",
        default="",
        help="Minimum acceptable PostgreSQL server version (e.g. 16.0).",
    )
    parser.add_argument(
        "--check-server-version",
        action="store_true",
        help="Run SHOW server_version_num via psql and evaluate freshness.",
    )
    parser.add_argument(
        "--server-dsn",
        default="",
        help="Optional DSN passed to psql for server version checks.",
    )
    parser.add_argument(
        "--server-psql-args",
        default="",
        help="Optional psql connection args for server checks, e.g. \"-h localhost -U teller -d prod\".",
    )
    parser.add_argument(
        "--fail-on-stale",
        action="store_true",
        help="Exit non-zero when freshness checks detect stale components.",
    )
    parser.add_argument(
        "--check-cves",
        action="store_true",
        help="Evaluate PostgreSQL client/server versions against CVE snapshot ranges.",
    )
    parser.add_argument(
        "--cve-snapshot",
        default="",
        help="Path to PostgreSQL CVE snapshot JSON payload.",
    )
    parser.add_argument(
        "--cve-policy",
        default="",
        help="Path to PostgreSQL CVE policy JSON payload.",
    )
    parser.add_argument(
        "--fail-on-cve",
        action="store_true",
        help="Exit non-zero when CVE policy is violated.",
    )
    parser.add_argument(
        "--refresh-cve-snapshot",
        action="store_true",
        help="Fetch latest PostgreSQL CVE data from postgresql.org before evaluation.",
    )
    return parser.parse_args()


def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    args = parse_args()
    output_json = Path(args.output_json)
    output_text = Path(args.output_text)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_text.parent.mkdir(parents=True, exist_ok=True)

    report = build_report(args)
    output_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text_report = format_text_report(report)
    output_text.write_text(text_report, encoding="utf-8")
    print(text_report, end="")

    if report["summary"]["gate_failed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
