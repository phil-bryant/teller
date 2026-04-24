# Security Scanning (SAST / DAST)

This project uses local script-based security checks (SAST and DAST).

## Tooling

- SAST:
  - `semgrep` (`p/security-audit`, `p/python`, and repo rules in `.semgrep.yml`)
  - `bandit` (config in `.bandit`)
  - `pip-audit`
  - `detect-secrets`
- DAST:
  - `schemathesis` against FastAPI OpenAPI
  - `OWASP ZAP` local CLI quick scan via `ZAP.sh` against local HTTP targets

Security tools are installed in an isolated virtualenv (`.security-venv`) by the runner script to avoid conflicts with app/runtime dependencies.

Manual install option (only if needed):

```bash
python3 -m venv .security-venv
./.security-venv/bin/pip install --upgrade pip
./.security-venv/bin/pip install -r requirements-security.txt
```

## One-command local lane

Run both SAST and DAST:

```bash
./17_run_security_checks.sh
```

Artifacts are written to `.security-reports/`.

### Target URLs and startup flow

`18_run_dast_checks.sh` starts the classification API automatically:

- classification API: `http://127.0.0.1:8787`
- OpenAPI schema: `http://127.0.0.1:8787/openapi.json`

Token capture server is optional and runs when possible:

- token capture API/UI: `http://127.0.0.1:8088`
- enabled by `RUN_TOKEN_CAPTURE_DAST=true`
- in `auto` mode, it runs only when `~/.teller/application_id.txt` exists

ZAP uses local CLI (not Docker). By default, the script uses `/Applications/ZAP.app/Contents/MacOS/ZAP.sh`.

## Gating policy

- Merge-blocking findings:
  - Semgrep findings with `ERROR` severity
  - Bandit findings with `HIGH` severity
  - Any `detect-secrets` finding
  - ZAP alerts with High risk
- Non-blocking but tracked:
  - Bandit `MEDIUM` / `LOW`
  - Semgrep `WARNING` / `INFO`
  - `pip-audit` dependency vulnerabilities (triage required due missing normalized severity)
  - ZAP Medium / Low / Informational alerts

### Exception process

For false positives or accepted risks:

1. Open an issue with scanner output and justification.
2. Add a scoped suppression:
   - Semgrep: `# nosemgrep: <rule-id>`
   - Bandit: `# nosec` with issue reference
   - ZAP: tune `.zap/rules.tsv`
3. Document expiration/revisit date for the exception.

## Script entrypoints

- `./17_run_security_checks.sh`: runs SAST and, by default, invokes DAST.
- `./18_run_dast_checks.sh`: runs DAST only.
