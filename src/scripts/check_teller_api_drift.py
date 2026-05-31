#!/usr/bin/env python3
#R001: Resolve Teller credentials with predictable local-token fallback behavior.
#R005: Run live canary checks when credentials exist and degrade safely otherwise.
#R010: Persist smoke artifacts and fail only on hard check failures.
#R015: Support strict live canary mode with live-only and warn-as-fail flags.
"""Run Teller API compatibility checks using live canary or local fallback."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BASE_URL = "https://api.teller.io"
HOME_TELLER_DIR = Path.home() / ".teller"


def read_text(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8").strip()


def read_token(path: Path) -> str:
    if not path.is_file():
        return ""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return ""
    return str(payload.get("current", "")).strip()


def discover_token_candidates() -> list[tuple[str, str]]:
    candidates: list[tuple[str, str]] = []
    default_token = read_token(HOME_TELLER_DIR / "auth_token.json")
    if default_token:
        candidates.append(("default", default_token))

    if HOME_TELLER_DIR.is_dir():
        for token_path in sorted(HOME_TELLER_DIR.glob("auth_token_*.json")):
            suffix = token_path.stem[len("auth_token_"):]
            token = read_token(token_path)
            if token:
                candidates.append((suffix, token))
    return candidates


def _resolve_cert_key_paths(cert_path: str, key_path: str) -> tuple[str, str]:
    resolved_cert = cert_path
    resolved_key = key_path
    if not resolved_cert:
        cert_candidate = HOME_TELLER_DIR / "certificate.pem"
        if cert_candidate.is_file():
            resolved_cert = str(cert_candidate)
    if not resolved_key:
        key_candidate = HOME_TELLER_DIR / "private_key.pem"
        if key_candidate.is_file():
            resolved_key = str(key_candidate)
    return resolved_cert, resolved_key


def _filter_token_candidates(
    candidates: list[tuple[str, str]],
    institution_id: str,
    warnings: list[str],
) -> list[tuple[str, str]]:
    if not institution_id:
        return candidates
    filtered = [item for item in candidates if item[0] == institution_id]
    if not filtered:
        warnings.append(
            f"No token candidates matched --institution-id={institution_id}. "
            "Set TELLER_ACCESS_TOKEN or choose a matching suffix."
        )
    return filtered


def _select_local_token(
    candidates: list[tuple[str, str]],
    institution_id: str,
    warnings: list[str],
) -> tuple[str, str]:
    filtered = _filter_token_candidates(candidates, institution_id, warnings)
    if institution_id:
        if len(filtered) > 1:
            warnings.append(
                f"Multiple token candidates matched --institution-id={institution_id}; "
                "set TELLER_ACCESS_TOKEN to disambiguate."
            )
            return "", ""
        return filtered[0] if filtered else ("", "")
    if len(filtered) == 1:
        return filtered[0]
    if len(filtered) > 1:
        warnings.append(
            "Multiple local Teller token files were found. "
            "Set TELLER_ACCESS_TOKEN or use --institution-id <suffix>."
        )
    return "", ""


def resolve_credentials(institution_id: str = "", run_all_tokens: bool = False) -> dict[str, Any]:
    cert_path = os.environ.get("TELLER_CERT_PATH", "").strip()
    key_path = os.environ.get("TELLER_KEY_PATH", "").strip()
    token = os.environ.get("TELLER_ACCESS_TOKEN", "").strip()
    token_source = "env:TELLER_ACCESS_TOKEN" if token else ""
    warnings: list[str] = []
    cert_path, key_path = _resolve_cert_key_paths(cert_path, key_path)
    if not token:
        candidates = discover_token_candidates()
        if run_all_tokens and candidates:
            candidates = _filter_token_candidates(candidates, institution_id, warnings)
            return {
                "cert_path": cert_path,
                "key_path": key_path,
                "token": "",
                "token_source": "",
                "token_candidates": candidates,
                "warnings": warnings,
            }
        token_source, token = _select_local_token(candidates, institution_id, warnings)

    return {
        "cert_path": cert_path,
        "key_path": key_path,
        "token": token,
        "token_source": token_source,
        "token_candidates": [(token_source, token)] if token else [],
        "warnings": warnings,
    }


def _run_live_check(
    *,
    requests,
    checks: list[dict[str, Any]],
    headers: dict[str, str],
    cert_pair: tuple[str, str],
    timeout_seconds: int,
    name: str,
    path: str,
    auth_token: str = "",
) -> None:
    auth = (auth_token, "") if auth_token else None
    url = f"{BASE_URL}{path}"
    check_result: dict[str, Any] = {
        "name": name,
        "url": url,
        "status": "pass",
        "http_status": None,
        "error": "",
    }
    try:
        response = requests.get(url, headers=headers, cert=cert_pair, auth=auth, timeout=timeout_seconds)
        check_result["http_status"] = response.status_code
        if response.status_code != 200:
            check_result["status"] = "fail"
            check_result["error"] = response.text[:500]
    except requests.RequestException as exc:
        check_result["status"] = "fail"
        check_result["error"] = str(exc)
    checks.append(check_result)


def _collect_source_checks(
    source_files: list[Path],
    endpoint_markers: list[str],
) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    for source_path in source_files:
        status = "pass"
        detail = ""
        if not source_path.is_file():
            status = "fail"
            detail = "Source file missing"
        else:
            text = source_path.read_text(encoding="utf-8")
            missing = [marker for marker in endpoint_markers if marker not in text]
            if missing:
                status = "warn"
                detail = f"Missing endpoint markers: {', '.join(missing)}"
        checks.append({"name": f"source:{source_path}", "status": status, "detail": detail})
    return checks


def _fallback_live_result(message: str) -> dict[str, Any]:
    return {
        "mode": "fallback",
        "status": "warn",
        "checks": [],
        "warnings": [message],
    }


def _run_authenticated_live_checks(
    *,
    requests,
    checks: list[dict[str, Any]],
    headers: dict[str, str],
    cert_pair: tuple[str, str],
    timeout_seconds: int,
    token: str,
    token_candidates: list[tuple[str, str]],
    run_all_tokens: bool,
    warnings: list[str],
) -> None:
    if run_all_tokens and token_candidates:
        for token_source, candidate_token in token_candidates:
            _run_live_check(
                requests=requests,
                checks=checks,
                headers=headers,
                cert_pair=cert_pair,
                timeout_seconds=timeout_seconds,
                name=f"accounts[{token_source}]",
                path="/accounts",
                auth_token=candidate_token,
            )
            _run_live_check(
                requests=requests,
                checks=checks,
                headers=headers,
                cert_pair=cert_pair,
                timeout_seconds=timeout_seconds,
                name=f"identity[{token_source}]",
                path="/identity",
                auth_token=candidate_token,
            )
        return
    if token:
        _run_live_check(
            requests=requests,
            checks=checks,
            headers=headers,
            cert_pair=cert_pair,
            timeout_seconds=timeout_seconds,
            name="accounts",
            path="/accounts",
            auth_token=token,
        )
        _run_live_check(
            requests=requests,
            checks=checks,
            headers=headers,
            cert_pair=cert_pair,
            timeout_seconds=timeout_seconds,
            name="identity",
            path="/identity",
            auth_token=token,
        )
        return
    warnings.append("Skipping /accounts and /identity checks: no usable Teller auth token was resolved.")


def run_live_canary(timeout_seconds: int, institution_id: str = "", run_all_tokens: bool = False) -> dict[str, Any]:
    try:
        import requests
    except ImportError:
        return _fallback_live_result("Skipping live canary: Python package 'requests' is not installed.")

    credentials = resolve_credentials(institution_id=institution_id, run_all_tokens=run_all_tokens)
    cert_path = credentials["cert_path"]
    key_path = credentials["key_path"]
    token = credentials["token"]
    token_candidates = [item for item in credentials.get("token_candidates", []) if item[1]]

    checks: list[dict[str, Any]] = []
    warnings: list[str] = list(credentials.get("warnings", []))

    if not cert_path or not key_path:
        return _fallback_live_result("Skipping live canary: Teller mTLS certificate/key not found.")

    cert_pair = (cert_path, key_path)
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    _run_live_check(
        requests=requests,
        checks=checks,
        headers=headers,
        cert_pair=cert_pair,
        timeout_seconds=timeout_seconds,
        name="institutions",
        path="/institutions",
    )
    _run_authenticated_live_checks(
        requests=requests,
        checks=checks,
        headers=headers,
        cert_pair=cert_pair,
        timeout_seconds=timeout_seconds,
        token=token,
        token_candidates=token_candidates,
        run_all_tokens=run_all_tokens,
        warnings=warnings,
    )

    failed = [check for check in checks if check["status"] == "fail"]
    status = "fail" if failed else ("warn" if warnings else "pass")
    return {"mode": "live", "status": status, "checks": checks, "warnings": warnings}


def run_fallback_checks() -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    expected_docs = [
        "teller-api-reference-institutions.md",
        "teller-api-reference-accounts.md",
        "teller-api-reference-identity.md",
    ]
    docs_dir = Path("docs/teller-api-reference")
    for filename in expected_docs:
        doc_path = docs_dir / filename
        checks.append(
            {
                "name": f"doc:{filename}",
                "status": "pass" if doc_path.is_file() else "fail",
                "detail": str(doc_path),
            }
        )

    source_files = [
        Path("src/macos-ui/Sources/TransactionClassifier/TellerSetupService.swift"),
        Path("src/macos-ui/Sources/TransactionClassifier/ConnectAPIClient.swift"),
        Path("10_run_classification_macos_ui.sh"),
        Path("07_fetch_teller_api_data.py"),
    ]
    endpoint_markers = ["/institutions", "/accounts", "/identity"]
    checks.extend(_collect_source_checks(source_files, endpoint_markers))

    failures = [check for check in checks if check["status"] == "fail"]
    warnings = [check for check in checks if check["status"] == "warn"]
    status = "fail" if failures else ("warn" if warnings else "pass")
    return {"mode": "fallback", "status": status, "checks": checks, "warnings": []}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check Teller API drift/compatibility.")
    parser.add_argument(
        "--output-json",
        default="artifacts/security/teller-api-drift.json",
        help="Path for JSON report output.",
    )
    parser.add_argument(
        "--output-text",
        default="artifacts/security/teller-api-drift.txt",
        help="Path for text summary output.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=15,
        help="HTTP timeout for live canary requests.",
    )
    parser.add_argument(
        "--institution-id",
        default="",
        help="Token suffix to use when multiple local auth_token_<suffix>.json files exist.",
    )
    parser.add_argument(
        "--run-all-tokens",
        action="store_true",
        help="Run authenticated checks for every discovered local token candidate.",
    )
    parser.add_argument(
        "--require-live",
        action="store_true",
        help="Fail when live canary cannot run and fallback mode is used.",
    )
    parser.add_argument(
        "--fail-on-warn",
        action="store_true",
        help="Treat warning status as a failure exit code.",
    )
    return parser.parse_args()


def build_text_report(report: dict[str, Any]) -> str:
    lines = [
        "Teller API smoke report",
        f"- Mode: {report['mode']}",
        f"- Status: {report['status']}",
        "",
    ]
    if report.get("warnings"):
        lines.append("Warnings:")
        for warning in report["warnings"]:
            lines.append(f"- {warning}")
        lines.append("")

    lines.append("Checks:")
    for check in report.get("checks", []):
        detail = check.get("detail", "") or check.get("error", "")
        http_status = check.get("http_status")
        suffix = f" (http {http_status})" if http_status else ""
        if detail:
            suffix = f"{suffix} {detail}".rstrip()
        lines.append(f"- [{check['status']}] {check['name']}{suffix}")
    return "\n".join(lines) + "\n"


def main() -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    args = parse_args()
    output_json = Path(args.output_json)
    output_text = Path(args.output_text)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_text.parent.mkdir(parents=True, exist_ok=True)

    live_result = run_live_canary(
        timeout_seconds=args.timeout_seconds,
        institution_id=args.institution_id,
        run_all_tokens=args.run_all_tokens,
    )
    used_fallback = live_result["mode"] == "fallback"
    if used_fallback:
        fallback_result = run_fallback_checks()
        merged_checks = fallback_result["checks"]
        merged_warnings = list(live_result.get("warnings", []))
        if fallback_result["status"] != "pass":
            merged_warnings.append("Fallback checks detected warnings/failures.")
        report = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "mode": "fallback",
            "status": fallback_result["status"],
            "warnings": merged_warnings,
            "checks": merged_checks,
        }
    else:
        report = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "mode": live_result["mode"],
            "status": live_result["status"],
            "warnings": live_result["warnings"],
            "checks": live_result["checks"],
        }

    output_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text_report = build_text_report(report)
    output_text.write_text(text_report, encoding="utf-8")
    print(text_report, end="")
    if args.require_live and used_fallback:
        return 1
    if report["status"] == "fail":
        return 1
    if args.fail_on_warn and report["status"] == "warn":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
