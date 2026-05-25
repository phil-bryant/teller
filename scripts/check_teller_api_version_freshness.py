#!/usr/bin/env python3
"""Check whether a newer Teller API version appears to be available."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import re
import shutil
import subprocess
import time
from http.cookiejar import CookieJar
from urllib.parse import parse_qs, urlencode, urljoin, urlsplit
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import HTTPCookieProcessor, Request, build_opener

try:
    import requests
except ModuleNotFoundError:  # pragma: no cover - dependency availability varies by runtime
    requests = None

DEFAULT_VERSION_URLS = (
    "https://teller.io/docs/api",
    "https://api.teller.io/openapi.json",
    "https://api.teller.io/swagger.json",
)


def parse_semver(value: str | None) -> tuple[int, int, int] | None:
    if not value:
        return None
    parts = re.findall(r"\d+", value)
    if not parts:
        return None
    while len(parts) < 3:
        parts.append("0")
    return int(parts[0]), int(parts[1]), int(parts[2])


def compare_versions(left: str | None, right: str | None) -> int | None:
    left_triplet = parse_semver(left)
    right_triplet = parse_semver(right)
    if left_triplet is None or right_triplet is None:
        return None
    if left_triplet < right_triplet:
        return -1
    if left_triplet > right_triplet:
        return 1
    return 0


def fetch_json(url: str, timeout_seconds: int) -> tuple[dict[str, Any] | None, str]:
    if requests is None:
        return None, "requests is required for Teller API version checks."
    parsed = urlsplit(url)
    if parsed.scheme.lower() != "https":
        return None, f"unsupported scheme for version source: {url}"
    try:
        response = requests.get(url, headers={"User-Agent": "teller-api-version-freshness/1.0"}, timeout=timeout_seconds)
        response.raise_for_status()
        payload = response.text
    except requests.RequestException as exc:
        return None, str(exc)
    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON: {exc}"
    if not isinstance(parsed, dict):
        return None, "response JSON was not an object"
    return parsed, ""


def fetch_text(url: str, timeout_seconds: int) -> tuple[str | None, str]:
    if requests is None:
        return None, "requests is required for Teller API version checks."
    parsed = urlsplit(url)
    if parsed.scheme.lower() != "https":
        return None, f"unsupported scheme for version source: {url}"
    try:
        response = requests.get(url, headers={"User-Agent": "teller-api-version-freshness/1.0"}, timeout=timeout_seconds)
        response.raise_for_status()
        payload = response.text
    except requests.RequestException as exc:
        return None, str(exc)
    return payload, ""


def fetch_text_with_opener(url: str, timeout_seconds: int, opener: Any) -> tuple[str | None, str]:
    request = Request(url, headers={"User-Agent": "teller-api-version-freshness/1.0"})
    try:
        with opener.open(request, timeout=timeout_seconds) as response:
            payload = response.read().decode("utf-8")
    except URLError as exc:
        return None, str(exc)
    return payload, ""


def extract_version_from_docs(text: str) -> str | None:
    # Teller docs currently phrase this as:
    # "Teller uses dated versions with the latest one being 2020-10-12."
    match = re.search(r"latest one being\s+(\d{4}-\d{2}-\d{2})", text, flags=re.I)
    if match:
        return match.group(1)
    return None


def extract_hidden_input(text: str, name: str) -> str | None:
    pattern = rf'name="{re.escape(name)}"[^>]*value="([^"]+)"'
    match = re.search(pattern, text, flags=re.I)
    if match:
        return match.group(1)
    return None


def resolve_otp_code(raw_value: str) -> str:
    text = (raw_value or "").strip()
    if not text:
        return ""
    digits_only = "".join(ch for ch in text if ch.isdigit())
    if len(digits_only) >= 6:
        return digits_only[:6]
    if text.startswith("otpauth://"):
        parsed = urlsplit(text)
        params = parse_qs(parsed.query)
        secret = (params.get("secret") or [""])[0].strip().replace(" ", "")
        if not secret:
            return ""
        try:
            secret_bytes = base64.b32decode(secret.upper(), casefold=True)
        except Exception:
            return ""
        period = int((params.get("period") or ["30"])[0] or "30")
        digits = int((params.get("digits") or ["6"])[0] or "6")
        counter = int(time.time() // max(period, 1))
        msg = counter.to_bytes(8, byteorder="big")
        digest = hmac.new(secret_bytes, msg, hashlib.sha1).digest()
        offset = digest[-1] & 0x0F
        binary = (
            ((digest[offset] & 0x7F) << 24)
            | (digest[offset + 1] << 16)
            | (digest[offset + 2] << 8)
            | digest[offset + 3]
        )
        code = str(binary % (10**digits)).zfill(digits)
        return code[:6]
    return ""


def read_1psa_field(item: str, field: str) -> str:
    if field == "password":
        password_cmd = subprocess.run(["1psa", "-p", item], capture_output=True, text=True, check=False)
        if password_cmd.returncode == 0 and password_cmd.stdout.strip():
            return password_cmd.stdout.strip()
    result = subprocess.run(["1psa", "-f", item, field], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def parse_dashboard_versions(page_text: str) -> dict[str, Any]:
    latest_match = re.search(r"latest API version\s*\((\d{4}-\d{2}-\d{2})\)", page_text, flags=re.I)
    current_match = re.search(r"currently using(?: the latest)? API version\s*\((\d{4}-\d{2}-\d{2})\)", page_text, flags=re.I)
    on_latest = bool(re.search(r"currently using the latest API version", page_text, flags=re.I))
    latest_version = latest_match.group(1) if latest_match else None
    current_version = current_match.group(1) if current_match else None
    if on_latest and current_version and not latest_version:
        latest_version = current_version
    if latest_version and current_version:
        comparison = compare_versions(current_version, latest_version)
        if comparison is not None:
            on_latest = comparison >= 0
        elif current_version == latest_version:
            on_latest = True
    return {
        "latest_version": latest_version,
        "current_version": current_version,
        "on_latest": on_latest if (latest_version or current_version) else None,
    }


def discover_dashboard_version(
    dashboard_url: str,
    psa_item: str,
    username_field: str,
    password_field: str,
    otp_field: str,
    timeout_seconds: int,
) -> tuple[dict[str, Any], list[str]]:
    warnings: list[str] = []
    result = {
        "checked": False,
        "status": "not-configured",
        "source_url": dashboard_url,
        "latest_version": None,
        "current_version": None,
        "on_latest": None,
    }
    if not psa_item:
        return result, warnings

    if shutil.which("1psa") is None:
        warnings.append("1psa not found; skipping Teller dashboard version check.")
        return result, warnings

    username = read_1psa_field(psa_item, username_field)
    password = read_1psa_field(psa_item, password_field)
    otp_raw = read_1psa_field(psa_item, otp_field) if otp_field else ""
    otp = resolve_otp_code(otp_raw)
    if not username or not password:
        warnings.append(f"Could not read Teller dashboard credentials from 1psa item '{psa_item}'.")
        return result, warnings

    cookies = CookieJar()
    opener = build_opener(HTTPCookieProcessor(cookies))
    login_page, login_error = fetch_text_with_opener(dashboard_url, timeout_seconds, opener)
    if login_page is None:
        warnings.append(f"Failed to load Teller dashboard login page: {login_error}")
        return result, warnings

    csrf_token = extract_hidden_input(login_page, "_csrf_token")
    if not csrf_token:
        warnings.append("Teller dashboard login page did not expose _csrf_token.")
        return result, warnings

    parsed = urlsplit(dashboard_url)
    login_url = urljoin(f"{parsed.scheme}://{parsed.netloc}", "/session")
    form_payload = {
        "_csrf_token": csrf_token,
        "session[email]": username,
        "session[username]": username,
        "session[password]": password,
    }
    if otp:
        form_payload["session[otp]"] = otp
        form_payload["session[one_time_password]"] = otp
    payload = urlencode(form_payload).encode("utf-8")
    login_request = Request(
        login_url,
        data=payload,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "teller-api-version-freshness/1.0",
        },
    )
    try:
        login_response = opener.open(login_request, timeout=timeout_seconds).read().decode("utf-8", errors="ignore")
    except Exception as exc:  # pragma: no cover - network/login path can vary
        warnings.append(f"Failed to submit Teller dashboard login form: {exc}")
        return result, warnings

    if "/session/mfa" in login_response or 'action="/session/mfa"' in login_response:
        mfa_csrf = extract_hidden_input(login_response, "_csrf_token")
        if not otp:
            result["checked"] = True
            result["status"] = "error"
            warnings.append("Teller dashboard requires MFA but OTP code was unavailable from 1psa.")
            return result, warnings
        if not mfa_csrf:
            result["checked"] = True
            result["status"] = "error"
            warnings.append("Teller dashboard MFA page did not expose _csrf_token.")
            return result, warnings
        mfa_payload = urlencode({"_csrf_token": mfa_csrf, "mfa[code]": otp}).encode("utf-8")
        mfa_request = Request(
            urljoin(f"{parsed.scheme}://{parsed.netloc}", "/session/mfa"),
            data=mfa_payload,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": "teller-api-version-freshness/1.0",
            },
        )
        try:
            opener.open(mfa_request, timeout=timeout_seconds).read()
        except Exception as exc:  # pragma: no cover
            result["checked"] = True
            result["status"] = "error"
            warnings.append(f"Failed to submit Teller dashboard MFA form: {exc}")
            return result, warnings

    dashboard_page, dashboard_error = fetch_text_with_opener(dashboard_url, timeout_seconds, opener)
    if dashboard_page is None:
        warnings.append(f"Failed to load Teller dashboard settings page after login: {dashboard_error}")
        return result, warnings
    if "You need to sign in or sign up before continuing." in dashboard_page:
        result["checked"] = True
        result["status"] = "error"
        warnings.append("Teller dashboard login was rejected; check 1psa credential/OTP fields.")
        return result, warnings

    parsed_versions = parse_dashboard_versions(dashboard_page)
    result["checked"] = True
    if parsed_versions["latest_version"] or parsed_versions["current_version"]:
        result["status"] = "ok"
        result["latest_version"] = parsed_versions["latest_version"]
        result["current_version"] = parsed_versions["current_version"]
        result["on_latest"] = parsed_versions["on_latest"]
    else:
        result["status"] = "error"
        warnings.append("Logged in to Teller dashboard but could not parse API version text.")
    return result, warnings


def discover_version(urls: list[str], timeout_seconds: int) -> tuple[str | None, str | None, list[str]]:
    warnings: list[str] = []
    for url in urls:
        if url.endswith("/docs/api"):
            text, error = fetch_text(url, timeout_seconds)
            if text is None:
                warnings.append(f"{url}: {error}")
                continue
            version = extract_version_from_docs(text)
            if version:
                return version, url, warnings
            warnings.append(f"{url}: could not locate latest dated version text")
            continue

        payload, error = fetch_json(url, timeout_seconds)
        if payload is None:
            warnings.append(f"{url}: {error}")
            continue
        info = payload.get("info")
        if isinstance(info, dict):
            version = str(info.get("version", "")).strip()
            if version:
                return version, url, warnings
        warnings.append(f"{url}: missing info.version")
    return None, None, warnings


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    sources = [item.strip() for item in args.version_sources.split(",") if item.strip()]
    if not sources:
        sources = list(DEFAULT_VERSION_URLS)
    dashboard, dashboard_warnings = discover_dashboard_version(
        dashboard_url=args.dashboard_url,
        psa_item=args.dashboard_psa_item,
        username_field=args.dashboard_username_field,
        password_field=args.dashboard_password_field,
        otp_field=args.dashboard_otp_field,
        timeout_seconds=args.timeout_seconds,
    )
    latest_version = dashboard.get("latest_version")
    source_url = dashboard.get("source_url") if latest_version else None
    warnings: list[str] = list(dashboard_warnings)
    if not latest_version:
        discovered_version, discovered_source, discovered_warnings = discover_version(sources, args.timeout_seconds)
        latest_version = discovered_version
        source_url = discovered_source
        warnings.extend(discovered_warnings)
    baseline = args.baseline_version.strip() or None
    status = "unknown"
    newer_available = None
    comparison = None
    if latest_version:
        status = "ok"
        if dashboard.get("checked") and dashboard.get("on_latest") is True:
            newer_available = False
        if baseline:
            comparison = compare_versions(baseline, latest_version)
            if comparison is None:
                newer_available = baseline != latest_version
            else:
                newer_available = comparison < 0
            if newer_available:
                status = "update-available"
    else:
        warnings.append("Could not determine Teller API version from configured sources.")

    gate_failed = bool(args.fail_on_new and newer_available is True)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "baseline_version": baseline,
        "latest_version": latest_version,
        "source_url": source_url,
        "dashboard": dashboard,
        "version_sources": sources,
        "newer_available": newer_available,
        "fail_on_new": args.fail_on_new,
        "gate_failed": gate_failed,
        "warnings": warnings,
    }


def format_report(report: dict[str, Any]) -> str:
    lines = [
        "Teller API version freshness report",
        f"- Status: {report['status']}",
        f"- Baseline version: {report['baseline_version'] or 'not configured'}",
        f"- Latest version: {report['latest_version'] or 'unknown'}",
        f"- Version source: {report['source_url'] or 'none resolved'}",
        f"- Dashboard status: {report['dashboard']['status']}",
        f"- Dashboard current version: {report['dashboard']['current_version'] or 'unknown'}",
        f"- Dashboard on latest: {report['dashboard']['on_latest'] if report['dashboard']['on_latest'] is not None else 'unknown'}",
        f"- Newer version available: {report['newer_available'] if report['newer_available'] is not None else 'unknown'}",
    ]
    if report["warnings"]:
        lines.append("- Warnings:")
        for warning in report["warnings"]:
            lines.append(f"  - {warning}")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check Teller API version freshness.")
    parser.add_argument("--output-json", default=".security-reports/teller-api-version-freshness.json")
    parser.add_argument("--output-text", default=".security-reports/teller-api-version-freshness.txt")
    parser.add_argument(
        "--version-sources",
        default=",".join(DEFAULT_VERSION_URLS),
        help="Comma-separated URLs returning OpenAPI/Swagger JSON with info.version.",
    )
    parser.add_argument("--baseline-version", default="", help="Expected Teller API version to compare against.")
    parser.add_argument("--timeout-seconds", type=int, default=15)
    parser.add_argument("--dashboard-url", default="https://teller.io/settings/application")
    parser.add_argument("--dashboard-psa-item", default="", help="Optional 1psa item containing dashboard credentials.")
    parser.add_argument("--dashboard-username-field", default="username")
    parser.add_argument("--dashboard-password-field", default="password")
    parser.add_argument("--dashboard-otp-field", default="one-time password")
    parser.add_argument("--fail-on-new", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_json = Path(args.output_json)
    output_text = Path(args.output_text)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_text.parent.mkdir(parents=True, exist_ok=True)
    report = build_report(args)
    output_json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    text = format_report(report)
    output_text.write_text(text, encoding="utf-8")
    print(text, end="")
    return 1 if report["gate_failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
