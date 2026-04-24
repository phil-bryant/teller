#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_SAST="${RUN_SAST:-true}"
RUN_DAST="${RUN_DAST:-true}"
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"
SECURITY_VENV_DIR="${SECURITY_VENV_DIR:-./.security-venv}"

mkdir -p "$REPORT_DIR"

#R001: Prefer project venv when available.
if [[ -d "./teller-venv" ]]; then
  # shellcheck disable=SC1091
  source "./teller-venv/bin/activate"
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Missing required command: $1"
    echo "Install security tooling with: pip install -r requirements-security.txt"
    exit 1
  fi
}

ensure_security_venv() {
  if [[ ! -d "$SECURITY_VENV_DIR" ]]; then
    echo "▶ Creating isolated security virtualenv at ${SECURITY_VENV_DIR}"
    python3 -m venv "$SECURITY_VENV_DIR"
  fi

  local security_pip="${SECURITY_VENV_DIR}/bin/pip"
  local security_semgrep="${SECURITY_VENV_DIR}/bin/semgrep"
  if [[ ! -x "$security_semgrep" ]]; then
    echo "▶ Installing security toolchain into ${SECURITY_VENV_DIR}"
    "$security_pip" install --upgrade pip
    "$security_pip" install -r requirements-security.txt
  fi
}

ensure_security_venv
export PATH="${SECURITY_VENV_DIR}/bin:${PATH}"

if [[ "$RUN_SAST" == "true" ]]; then
  require_command semgrep
  require_command bandit
  require_command pip-audit
  require_command detect-secrets

  echo "▶ Running Semgrep"
  semgrep scan \
    --config "p/security-audit" \
    --config "p/python" \
    --config ".semgrep.yml" \
    --json \
    --output "${REPORT_DIR}/semgrep.json" \
    .

  echo "▶ Running Bandit"
  set +e
  bandit -q -r ./teller -c ./.bandit -f json -o "${REPORT_DIR}/bandit.json"
  BANDIT_EXIT=$?
  set -e
  if [[ "$BANDIT_EXIT" -gt 1 ]]; then
    echo "❌ Bandit failed to execute."
    exit 1
  fi

  echo "▶ Running pip-audit"
  set +e
  pip-audit --format json --output "${REPORT_DIR}/pip-audit.json"
  PIP_AUDIT_EXIT=$?
  set -e
  if [[ "$PIP_AUDIT_EXIT" -gt 1 ]]; then
    echo "❌ pip-audit failed to execute."
    exit 1
  fi

  echo "▶ Running detect-secrets"
  detect-secrets scan --all-files --force-use-all-plugins \
    --exclude-files '(^\.git/|^teller-venv/|^backups/|^archive/backup_extracts/|^bank_statements/|^teller-connect-ui/)' \
    > "${REPORT_DIR}/detect-secrets.json"

  python3 - <<'PY' "${REPORT_DIR}" "${FAIL_ON_HIGH_CRITICAL}"
import json
import os
import sys
from pathlib import Path

report_dir = Path(sys.argv[1])
fail_on_high = sys.argv[2].lower() == "true"

semgrep_path = report_dir / "semgrep.json"
bandit_path = report_dir / "bandit.json"
pip_audit_path = report_dir / "pip-audit.json"
secrets_path = report_dir / "detect-secrets.json"

for required in [semgrep_path, bandit_path, pip_audit_path, secrets_path]:
    if not required.exists():
        print(f"Missing report file: {required}")
        sys.exit(1)

with semgrep_path.open("r", encoding="utf-8") as fh:
    semgrep = json.load(fh)
semgrep_results = semgrep.get("results", []) if isinstance(semgrep, dict) else []
semgrep_high = sum(1 for item in semgrep_results if item.get("extra", {}).get("severity") == "ERROR")
semgrep_total = len(semgrep_results)

with bandit_path.open("r", encoding="utf-8") as fh:
    bandit = json.load(fh)
bandit_results = bandit.get("results", []) if isinstance(bandit, dict) else []
bandit_high = sum(1 for item in bandit_results if item.get("issue_severity") == "HIGH")
bandit_total = len(bandit_results)

with pip_audit_path.open("r", encoding="utf-8") as fh:
    pip_audit = json.load(fh)
if isinstance(pip_audit, list):
    dep_vulns = sum(len(item.get("vulns", [])) for item in pip_audit)
else:
    dep_vulns = len(pip_audit.get("vulns", [])) if isinstance(pip_audit, dict) else 0

with secrets_path.open("r", encoding="utf-8") as fh:
    secrets = json.load(fh)
secret_results = secrets.get("results", {}) if isinstance(secrets, dict) else {}
secret_findings = 0
for findings in secret_results.values():
    if isinstance(findings, list):
        secret_findings += len(findings)

high_critical_total = semgrep_high + bandit_high + secret_findings

summary = {
    "semgrep_total": semgrep_total,
    "semgrep_high_critical": semgrep_high,
    "bandit_total": bandit_total,
    "bandit_high_critical": bandit_high,
    "pip_audit_vulnerabilities": dep_vulns,
    "detect_secrets_findings": secret_findings,
    "high_critical_total": high_critical_total,
    "gate_failed": fail_on_high and high_critical_total > 0,
}

summary_path = report_dir / "sast-summary.json"
with summary_path.open("w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
    fh.write("\n")

print("SAST summary")
print(json.dumps(summary, indent=2))

if fail_on_high and high_critical_total > 0:
    print("❌ SAST gate failed: High/Critical findings detected.")
    sys.exit(1)
PY
fi

if [[ "$RUN_DAST" == "true" ]]; then
  ./18_run_dast_checks.sh
fi

echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
