# Run Security Checks Requirements

## Scope

Applies to `15_run_security_checks.sh`.

R001  Statement: Run in strict shell mode and execute from repository root.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- Run from a non-root working directory and verify relative paths still resolve.

R005  Statement: Bootstrap an isolated security toolchain environment before scanning.
Design: Create `SECURITY_VENV_DIR` when missing, install `requirements-security.txt` when `semgrep` is absent in that venv, and prepend `${SECURITY_VENV_DIR}/bin` to `PATH`.
Tests:
- Remove `.security-venv`, run script, and verify venv creation plus tool installation path executes.

R010  Statement: Prefer project runtime virtualenv for dependency-targeted scans.
Design: Activate `./teller-venv` when present and set `PIPAPI_PYTHON_LOCATION` to the project interpreter so `pip-audit` evaluates app dependencies instead of the security toolchain venv.
Tests:
- Run with `./teller-venv` present and verify pip-audit target interpreter output references project Python.

R015  Statement: Support configurable execution lanes and report destination.
Design: Resolve `SECURITY_REPORT_DIR`, `RUN_SAST`, `RUN_DAST`, `RUN_MACOS_UI_DAST`, and `SECURITY_FAIL_ON_HIGH_CRITICAL` from environment with safe defaults; always create the report directory before writing artifacts.
Tests:
- Set `RUN_SAST=false` and `RUN_DAST=false` and verify script exits cleanly after setup.

R020  Statement: Run SAST scanners and persist machine-readable artifacts.
Design: Require `semgrep`, `bandit`, `pip-audit`, and `detect-secrets`; execute scans with project configs and write JSON outputs under the report directory. When Swift sources are present under `./macos-ui` and `RUN_SWIFT_SAST=true`, run `swiftlint lint --reporter json` with focused security rules (`force_cast`, `force_try`, `force_unwrapping`) against first-party `Sources`/`Tests`/`UITests`, and persist `swiftlint.json` in the report directory.
Tests:
- Run SAST lane and verify `semgrep.json`, `bandit.json`, `pip-audit.json`, `detect-secrets.json`, and `swiftlint.json` are produced.

R025  Statement: Distinguish scanner findings from scanner execution failures.
Design: Treat `bandit`/`pip-audit`/`schemathesis` exit codes greater than `1` as hard execution failures; allow exit code `1` as "findings detected" so gating remains centralized (`sast-summary.json` for SAST and ZAP high/critical parsing for DAST).
Tests:
- Stub `bandit` to return `2` and verify script exits with explicit execution failure.

R030  Statement: Produce a consolidated SAST gate summary and enforce blocking policy.
Design: Aggregate Semgrep `ERROR`, Bandit `HIGH`, SwiftLint `error`, and all detect-secrets findings into `sast-summary.json`; fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and high/critical totals are non-zero.
Tests:
- Seed report fixtures with one high-severity finding and verify gate failure when fail-on-high is enabled.

R035  Statement: Start local classification API automatically for DAST execution.
Design: Launch `14_run_classification_api.py` on resolved host/port values, wait for `/health`, and always clean up spawned background processes with an EXIT trap.
Tests:
- Run DAST lane and verify API process is started, health-check gated, and terminated on completion.

R040  Statement: Support optional token-capture DAST coverage with auto-detection.
Design: Resolve `RUN_TOKEN_CAPTURE_DAST` in `true|false|auto` mode; in `auto`, enable token-capture scanning only when `~/.teller/application_id.txt` exists.
Tests:
- Run with `RUN_TOKEN_CAPTURE_DAST=auto` and no application ID file and verify token-capture DAST is skipped.

R045  Statement: Run Schemathesis and ZAP quick scans with configurable targets and high/critical gating.
Design: Run Schemathesis against resolved OpenAPI URL (using positive-mode generation and runtime fixture examples for live IDs). Before Schemathesis, execute a deterministic contract check that creates and deletes a category (including second-delete 404 semantics) and persist its JSON/log artifacts. Exclude `/v1/categories/{nys_snw_category_id}` from Schemathesis fuzz/stateful generation to avoid non-deterministic resource-lifecycle skew now covered by the deterministic check. Run ZAP CLI quick scans against classification and optional token-capture targets, parse any generated ZAP JSON alerts, and fail when high/critical alerts exist and fail-on-high is enabled.
Tests:
- Configure `RUN_ZAP=true` with missing `ZAP_CLI_CMD` and verify explicit prerequisite failure.
- Configure DAST with valid tooling and verify zap/schemathesis logs are written in the report directory.

R050  Statement: Emit explicit completion status and artifact location for operators.
Design: Print SAST/DAST progress markers, gate outcomes, and explicit lane completion lines (`Static Application Security Testing (SAST) checks completed.` and `Dynamic Application Security Testing (DAST) checks completed.`) plus final success output including resolved report directory path.
Tests:
- Run a passing lane and verify final completion output includes the reports path.

R055  Statement: Delimit every security tool run with a bounded header that includes purpose and official URL.
Design: Before each scanner invocation (Semgrep, Bandit, pip-audit, detect-secrets, SwiftLint, Schemathesis, OWASP ZAP), print an ASCII box header containing the tool name, no more than two explainer lines describing what the test does, and a line with the tool's official URL.
Tests:
- Run a passing SAST lane and verify output includes boxed header lines, at least one two-line explainer, and URL lines for SAST tools.

R060  Statement: Support local macOS UI Dynamic Application Security Testing (DAST) through OWASP ZAP proxying.
Design: When `RUN_MACOS_UI_DAST=true`, require `RUN_ZAP=true`, start OWASP ZAP in daemon/proxy mode on `MACOS_UI_DAST_ZAP_PROXY_HOST`/`MACOS_UI_DAST_ZAP_PROXY_PORT`, run `./06_run_macos_ui_regression_tests.sh` in XCUITest-only mode with `TELLER_CLASSIFIER_API_URL` + `TELLER_CLASSIFIER_HTTP_PROXY`, and emit `zap-macos-ui.json`, `zap-macos-ui.html`, and `macos-ui-dast-xcuitest.log` under the report directory. Support `MACOS_UI_DAST_REUSE_EXISTING_API=true` to skip launching a new API process.
Tests:
- Set `RUN_MACOS_UI_DAST=true` with `RUN_ZAP=false` and verify explicit prerequisite failure.
- Set `RUN_MACOS_UI_DAST=true` with stubbed ZAP/API/UI scripts and verify proxy startup, UI regression invocation, and macOS UI DAST artifacts.

R065  Statement: Run ClamAV repository malware scans and include findings in SAST gating.
Design: When `RUN_SAST=true` and `RUN_CLAMAV=true`, require `clamscan`, run a recursive repository scan, persist `clamav.log` and `clamav-summary.json`, treat exit code `1` as findings (not execution failure), and include infected file counts in `sast-summary.json` high/critical totals. Print signature freshness metadata (latest DB file timestamp/age) before scan execution, print the fully resolved scan target directory/path, and emit periodic progress heartbeat lines while ClamAV runs so long scans are not silent. If ClamAV reports missing signature databases (`No supported database files found`), run one-time `freshclam --stdout` refresh (bootstrapping config from Homebrew sample when needed) and retry the scan once before failing.
Tests:
- Run SAST lane with clean ClamAV output and verify `clamav.log`, `clamav-summary.json`, and `clamav_infected_files` summary field are produced.
- Stub ClamAV to return exit code `2` and verify explicit execution failure.
- Stub ClamAV to return exit code `1` with infected files and verify SAST gate failure when fail-on-high is enabled.
- Stub missing ClamAV databases on first scan, verify `freshclam --stdout` runs, and verify the script retries ClamAV once.
- Run ClamAV lane and verify output includes signature freshness metadata, explicit scan target path, and at least one in-progress heartbeat line for long-running scans.

## Changelog

- 2026-04-24: Consolidated security scanning policy and runtime behavior from `docs/security-scanning.md` into script-scoped requirements for `15_run_security_checks.sh`.
- 2026-04-26: Added R065 to require ClamAV repository scans with summarized findings and SAST gate integration.
- 2026-04-26: Added boxed per-tool headers with brief explainers and official URLs for all security scanners.
- 2026-04-26: Added local macOS UI DAST requirements for OWASP ZAP proxy-driven XCUITest coverage.
