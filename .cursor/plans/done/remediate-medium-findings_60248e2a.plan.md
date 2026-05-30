---
name: remediate-medium-findings
overview: "Remediate all 10 medium findings with secure-by-default fixes now, using your selected policies: #8 local-only classifier API URL, #9 pinned trusted 1psa paths without override, and #10 light HTML sanitization."
todos:
  - id: fix-db-sql-injection-paths
    content: "Implement #1 #2 #3 SQL-safe quoting and strict identifier validation across deploy/destroy/restore scripts"
    status: pending
  - id: fix-dast-redaction-and-restore-integrity
    content: "Implement #4 log redaction parity and #5 backup/globals integrity + permission hardening"
    status: pending
  - id: fix-macos-bridge-networking-and-token-paths
    content: "Implement #6 #7 #8 #9 hardening in ConnectView/ConnectAPIClient/APIClient with chosen defaults"
    status: pending
  - id: fix-email-html-rendering
    content: "Implement #10 light sanitization and embedded webview navigation restrictions"
    status: pending
  - id: add-tests-and-run-regressions
    content: Add/adjust shell and Swift tests for all findings and run target test suites
    status: pending
isProject: false
---

# Remediation Plan for Medium Findings (1-10)

## Scope and Defaults
- Implement all findings in one pass.
- Enforce secure-by-default behavior immediately for script and macOS issues.
- Apply your decisions:
  - #8: local-only classifier API hosts by default.
  - #9: pinned absolute trusted `1psa` paths with no override.
  - #10: light HTML sanitization (not strict stripping).

## Changes by Finding
- **#1 SQL Injection via profile DB name**
  - Update SQL call sites in:
    - [`/Users/phil/local/src/teller/05_deploy_database.sh`](/Users/phil/local/src/teller/05_deploy_database.sh)
    - [`/Users/phil/local/src/teller/98_destroy_database.sh`](/Users/phil/local/src/teller/98_destroy_database.sh)
    - [`/Users/phil/local/src/teller/99_restore_database.sh`](/Users/phil/local/src/teller/99_restore_database.sh)
  - Replace shell string interpolation in SQL with `psql -v` variables and server-side quoting (`format`, `quote_literal` / `:'var'` patterns).
  - Add strict identifier validation helper(s) for DB name inputs before use.

- **#2 SQL Injection via managed schema name**
  - In [`/Users/phil/local/src/teller/98_destroy_database.sh`](/Users/phil/local/src/teller/98_destroy_database.sh), validate schema as a single identifier and execute `DROP SCHEMA` using SQL identifier quoting in PostgreSQL instead of shell interpolation.

- **#3 SQL Injection via scoped restore table name**
  - In [`/Users/phil/local/src/teller/99_restore_database.sh`](/Users/phil/local/src/teller/99_restore_database.sh), validate `--table` as `schema.identifier` (or default schema + identifier), and generate repair SQL using quoted identifiers server-side.

- **#4 Static DAST log token leak**
  - Align static lane redaction behavior with dynamic lane:
    - [`/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh)
    - [`/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_dynamic_security_lane.sh)
    - Shared helper in [`/Users/phil/local/src/teller/src/scripts/security/common.sh`](/Users/phil/local/src/teller/src/scripts/security/common.sh)
  - Ensure Schemathesis text/JUnit artifacts are redacted before persistence.

- **#5 Globals replay integrity gap**
  - Add dump+globals integrity verification via manifest/hash pair:
    - Backup emission in [`/Users/phil/local/src/teller/97_backup_database.sh`](/Users/phil/local/src/teller/97_backup_database.sh)
    - Restore verification in [`/Users/phil/local/src/teller/99_restore_database.sh`](/Users/phil/local/src/teller/99_restore_database.sh)
  - Harden restore input permissions to owner-only defaults where scripts create artifacts.

- **#6 Unauthenticated Connect WebView bridge**
  - In [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ConnectView.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ConnectView.swift), require trusted message origin/frame checks and a per-session nonce on bridge success messages before token persistence.

- **#7 Token exposure via curl argv**
  - In [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ConnectAPIClient.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/ConnectAPIClient.swift), replace curl subprocess identity call with in-process networking so tokens never appear in process args.

- **#8 Remote classifier API URL exfiltration**
  - In [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/APIClient.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/APIClient.swift), restrict base URL hosts to local loopback (`localhost`, `127.0.0.1`, `::1`) by default.
  - Fail fast on non-loopback hosts.

- **#9 PATH-based `1psa` hijack**
  - In [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/APIClient.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/APIClient.swift), remove `/usr/bin/env 1psa` lookup.
  - Resolve token only via pinned trusted absolute `1psa` path candidates (no user override).

- **#10 Untrusted Mailcart HTML active content**
  - In:
    - [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift)
    - [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/EmailAmountScrollSupport.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/EmailAmountScrollSupport.swift)
  - Implement light sanitization to remove high-risk active elements/attributes while preserving typical receipt rendering.
  - Add navigation blocking policy for embedded email view content.

## Test and Verification Plan
- Shell/script regression:
  - [`/Users/phil/local/src/teller/tests/sh/05_deploy_database.bats`](/Users/phil/local/src/teller/tests/sh/05_deploy_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats`](/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/99_restore_database.bats`](/Users/phil/local/src/teller/tests/sh/99_restore_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/t03_run_static_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/t03_run_static_security_tests.bats)
  - [`/Users/phil/local/src/teller/tests/sh/t12_run_dynamic_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/t12_run_dynamic_security_tests.bats)
- Swift/macOS regression:
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/APIClientTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectAPIClientTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/ConnectAPIClientTests.swift)
  - [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/LocalClassifierTLSTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/LocalClassifierTLSTests.swift)
- Run existing suites:
  - `./tests/t10_run_swift_unit_tests.sh`
  - `./tests/t14_run_macos_ui_regression_tests.sh`
  - `./tests/t03_run_static_security_tests.sh`

## Delivery Notes
- Prioritize script safety primitives first (#1-#5), then macOS client hardening (#6-#10), then full regression pass.
- Keep behavior changes explicit in error messages so operators understand rejected inputs/configurations.
- Update requirement docs where acceptance criteria changed (especially #8 and #9 defaults).