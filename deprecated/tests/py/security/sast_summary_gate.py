#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def count_pip_audit(payload) -> int:
    if isinstance(payload, list):
        return sum(len(item.get("vulns", [])) for item in payload if isinstance(item, dict))
    if isinstance(payload, dict) and isinstance(payload.get("dependencies"), list):
        return sum(len(dep.get("vulns", [])) for dep in payload["dependencies"] if isinstance(dep, dict))
    if isinstance(payload, dict):
        vulns = payload.get("vulns", [])
        return len(vulns) if isinstance(vulns, list) else 0
    return 0


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: sast_summary_gate.py <report_dir> <fail_gate_bool> <policy_mode: medium|high>"
        )
    report_dir = Path(sys.argv[1])
    fail_gate = sys.argv[2].lower() == "true"
    policy_mode = sys.argv[3].strip().lower()
    semgrep = load_json(report_dir / "semgrep.json")
    bandit = load_json(report_dir / "bandit.json")
    pip_audit = load_json(report_dir / "pip-audit.json")
    secrets = load_json(report_dir / "detect-secrets.json")
    swiftlint = load_json(report_dir / "swiftlint.json")
    shellcheck = load_json(report_dir / "shellcheck.json")
    gitleaks = load_json(report_dir / "gitleaks.json")
    ruff_payload = load_json(report_dir / "ruff.json") if (report_dir / "ruff.json").exists() else []

    semgrep_results = semgrep.get("results", []) if isinstance(semgrep, dict) else []
    bandit_results = bandit.get("results", []) if isinstance(bandit, dict) else []
    secret_results = secrets.get("results", {}) if isinstance(secrets, dict) else {}
    swiftlint_results = swiftlint if isinstance(swiftlint, list) else []
    shellcheck_results = shellcheck if isinstance(shellcheck, list) else []
    ruff_results = ruff_payload if isinstance(ruff_payload, list) else []

    semgrep_high = sum(1 for item in semgrep_results if item.get("extra", {}).get("severity") == "ERROR")
    semgrep_medium = sum(
        1
        for item in semgrep_results
        if str(item.get("extra", {}).get("severity", "")).upper() in {"WARNING", "ERROR", "CRITICAL"}
    )
    bandit_high = sum(1 for item in bandit_results if item.get("issue_severity") == "HIGH")
    bandit_medium = sum(
        1 for item in bandit_results if str(item.get("issue_severity", "")).upper() in {"MEDIUM", "HIGH"}
    )
    dep_vulns = count_pip_audit(pip_audit)
    secret_findings = sum(len(v) for v in secret_results.values() if isinstance(v, list))
    swiftlint_high = sum(1 for item in swiftlint_results if str(item.get("severity", "")).lower() == "error")
    swiftlint_medium = sum(
        1 for item in swiftlint_results if str(item.get("severity", "")).lower() in {"warning", "error"}
    )
    shellcheck_high = sum(1 for item in shellcheck_results if str(item.get("level", "")).lower() == "error")
    shellcheck_medium = sum(
        1 for item in shellcheck_results if str(item.get("level", "")).lower() in {"warning", "error"}
    )
    if isinstance(gitleaks, list):
        gitleaks_findings = len(gitleaks)
    elif isinstance(gitleaks, dict) and isinstance(gitleaks.get("findings"), list):
        gitleaks_findings = len(gitleaks.get("findings", []))
    else:
        gitleaks_findings = 0
    ruff_total = len(ruff_results)
    high_total = semgrep_high + bandit_high + secret_findings + swiftlint_high + shellcheck_high + gitleaks_findings + ruff_total
    medium_total = (
        semgrep_medium
        + bandit_medium
        + dep_vulns
        + secret_findings
        + swiftlint_medium
        + shellcheck_medium
        + gitleaks_findings
        + ruff_total
    )
    if policy_mode == "high":
        gate_total = high_total
        gate_policy = "high-critical"
    else:
        gate_total = medium_total
        gate_policy = "financial-app-medium-or-higher-blocking"
    summary = {
        "semgrep_total": len(semgrep_results),
        "semgrep_high_critical": semgrep_high,
        "semgrep_medium_or_higher": semgrep_medium,
        "bandit_total": len(bandit_results),
        "bandit_high_critical": bandit_high,
        "bandit_medium_or_higher": bandit_medium,
        "pip_audit_vulnerabilities": dep_vulns,
        "detect_secrets_findings": secret_findings,
        "ruff_total": ruff_total,
        "ruff_high_critical": ruff_total,
        "ruff_medium_or_higher": ruff_total,
        "shellcheck_total": len(shellcheck_results),
        "shellcheck_high_critical": shellcheck_high,
        "shellcheck_medium_or_higher": shellcheck_medium,
        "gitleaks_findings": gitleaks_findings,
        "swiftlint_total": len(swiftlint_results),
        "swiftlint_high_critical": swiftlint_high,
        "swiftlint_medium_or_higher": swiftlint_medium,
        "high_critical_total": high_total,
        "medium_or_higher_total": medium_total,
        "gate_policy": gate_policy,
        "gate_failed": fail_gate and gate_total > 0,
    }
    summary_path = report_dir / "sast-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("Static Application Security Testing (SAST) summary")
    print(json.dumps(summary, indent=2))
    if fail_gate and gate_total > 0:
        if policy_mode == "high":
            print("❌ Static Application Security Testing (SAST) gate failed: High/Critical findings detected.")
        else:
            print("❌ Static Application Security Testing (SAST) gate failed: Medium-or-higher findings detected.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
