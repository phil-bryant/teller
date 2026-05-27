#!/usr/bin/env python3
#R001: Resolve Teller credentials with predictable local-token fallback behavior.
#R005: Run live canary checks when credentials exist and degrade safely otherwise.
#R010: Persist smoke artifacts and fail only on hard check failures.
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


def resolve_credentials(institution_id: str = "", run_all_tokens: bool = False) -> dict[str, Any]:
    cert_path = os.environ.get("TELLER_CERT_PATH", "").strip()
    key_path = os.environ.get("TELLER_KEY_PATH", "").strip()
    token = os.environ.get("TELLER_ACCESS_TOKEN", "").strip()
    token_source = "env:TELLER_ACCESS_TOKEN" if token else ""
    warnings: list[str] = []

    if not cert_path:
        candidate = HOME_TELLER_DIR / "certificate.pem"
        if candidate.is_file():
            cert_path = str(candidate)
    if not key_path:
        candidate = HOME_TELLER_DIR / "private_key.pem"
        if candidate.is_file():
            key_path = str(candidate)
    if not token:
        candidates = discover_token_candidates()
        if run_all_tokens and candidates:
            if institution_id:
                filtered = [item for item in candidates if item[0] == institution_id]
                if not filtered:
                    warnings.append(
                        f"No token candidates matched --institution-id={institution_id}. "
                        "Set TELLER_ACCESS_TOKEN or choose a matching suffix."
                    )
                candidates = filtered
            return {
                "cert_path": cert_path,
                "key_path": key_path,
                "token": "",
                "token_source": "",
                "token_candidates": candidates,
                "warnings": warnings,
            }
        if institution_id:
            filtered = [item for item in candidates if item[0] == institution_id]
            if not filtered:
                warnings.append(
                    f"No token candidates matched --institution-id={institution_id}. "
                    "Set TELLER_ACCESS_TOKEN or choose a matching suffix."
                )
            elif len(filtered) > 1:
                warnings.append(
                    f"Multiple token candidates matched --institution-id={institution_id}; "
                    "set TELLER_ACCESS_TOKEN to disambiguate."
                )
            else:
                token_source, token = filtered[0]
        else:
            if len(candidates) == 1:
                token_source, token = candidates[0]
            elif len(candidates) > 1:
                warnings.append(
                    "Multiple local Teller token files were found. "
                    "Set TELLER_ACCESS_TOKEN or use --institution-id <suffix>."
                )

    return {
        "cert_path": cert_path,
        "key_path": key_path,
        "token": token,
        "token_source": token_source,
        "token_candidates": [(token_source, token)] if token else [],
        "warnings": warnings,
    }


def run_live_canary(timeout_seconds: int, institution_id: str = "", run_all_tokens: bool = False) -> dict[str, Any]:
    try:
        import requests
    except ImportError:
        return {
            "mode": "fallback",
            "status": "warn",
            "checks": [],
            "warnings": ["Skipping live canary: Python package 'requests' is not installed."],
        }

    credentials = resolve_credentials(institution_id=institution_id, run_all_tokens=run_all_tokens)
    cert_path = credentials["cert_path"]
    key_path = credentials["key_path"]
    token = credentials["token"]
    token_candidates = [item for item in credentials.get("token_candidates", []) if item[1]]

    checks: list[dict[str, Any]] = []
    warnings: list[str] = list(credentials.get("warnings", []))

    if not cert_path or not key_path:
        return {
            "mode": "fallback",
            "status": "warn",
            "checks": [],
            "warnings": ["Skipping live canary: Teller mTLS certificate/key not found."],
        }

    cert_pair = (cert_path, key_path)
    headers = {"Accept": "application/json", "Content-Type": "application/json"}

    def run_check(name: str, path: str, auth_token: str = "") -> None:
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

    run_check("institutions", "/institutions")
    if run_all_tokens and token_candidates:
        for token_source, candidate_token in token_candidates:
            run_check(f"accounts[{token_source}]", "/accounts", auth_token=candidate_token)
            run_check(f"identity[{token_source}]", "/identity", auth_token=candidate_token)
    elif token:
        run_check("accounts", "/accounts", auth_token=token)
        run_check("identity", "/identity", auth_token=token)
    else:
        warnings.append("Skipping /accounts and /identity checks: no usable Teller auth token was resolved.")

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
        Path("09_run_classification_macos_ui.sh"),
        Path("06_fetch_teller_api_data.py"),
    ]
    endpoint_markers = ["/institutions", "/accounts", "/identity"]
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
    if live_result["mode"] == "fallback":
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
    return 1 if report["status"] == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
