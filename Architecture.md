# Architecture

Teller-owned architecture reference: Teller bank ingest, the `teller.*` schema, DB profiles, backup/restore,
shared DB/session helpers, the local test/security stack, and OCR statement-line reconstruction.

For the cross-repo ecosystem view (Teller ↔ Matchy ↔ Mailcart system landscape and trigger flow), see the
eggnest root [`../Architecture.md`](../Architecture.md). Classification API / macOS UI architecture lives in
[`../classy/Architecture.md`](../classy/Architecture.md); matching/scoring algorithms in
[`../matchy/README.md`](../matchy/README.md); Outlook/Graph search internals in
[`../mailcart/README.md`](../mailcart/README.md).

## Tech Stack Overview

```text
TELLER TECH STACK (repo: /Users/phil/local/src/teller)
=======================================================

 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                                EXTERNAL SYSTEMS                              │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ - Teller API (api.teller.io)                                                 │
 │ - 1psa secret store CLI                                                      │
 │ - Mailcart local service (optional)                                          │
 └───────────────────────────────────────┬──────────────────────────────────────┘
                                         |
                                         v
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                              PYTHON BACKEND LAYER                            │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ Runtime: Python 3.10+ (venv; prefers 3.12 in setup script)                   │
 │ Frameworks/Libs: FastAPI, Starlette, Uvicorn, Pydantic, SQLAlchemy,          │
 │                  psycopg2-binary, requests, structlog, python-dotenv         │
 │ Main flows:                                                                  │
 │   - Ingest: 07_fetch_teller_api_data.py                                      │
 │   - Backfill: 08_backfill_bank_statements.py                                 │
 │   - API: 09_run_classification_api.py ->                                     │
 │         src/teller/teller_classification_api.py -> src/teller/classification │
 └───────────────────────────────────────┬──────────────────────────────────────┘
                                         |
                                         v
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                            DATA / PERSISTENCE LAYER                          │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ Database target (local profile or managed profile via db profiles)           │
 │ PostgreSQL path: src/sql/postgres/                                           │
 │ SQLite path: existing script entrypoints with sqlite profile branching        │
│ SQLite money storage: integer cents for amount/running_balance/ledger/available │
│ Current dependency: Teller account currency is USD for sqlite money encoding  │
 │ DB helpers in: src/teller/teller_db.py,                                      │
 │                  src/teller/teller_db_profile.py                             │
 └───────────────────────────────────────┬──────────────────────────────────────┘
                                         ^
                                         |
 ┌───────────────────────────────────────┴──────────────────────────────────────┐
 │                              MACOS APP / UI LAYER                            │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ Swift 5.9, SwiftUI, macOS 14+                                                │
 │ Package: src/macos-ui/Package.swift                                          │
 │ App: TransactionClassifier                                                   │
 │ Includes WKWebView Connect flows + PLCrashReporter                           │
 └──────────────────────────────────────────────────────────────────────────────┘


AUTOMATION AND OPERATIONS
=========================

┌──────────────────────────────────────────────────────────────────────────┐
│ Numbered workflow scripts (project root)                                 │
├──────────────────────────────────────────────────────────────────────────┤
│ 01-04 setup (prereqs, venv, dependencies, classifier TLS)                │
│ 05    DB deploy                                                          │
│ 06-07 ingest + bank-statement backfill                                   │
│ 08-09 classification API + macOS UI launcher                             │
│ 10    parallel aggregate test runner                                     │
│ 11-13 quality trends / target / telemetry pruning                        │
│ 97-99 backup / destroy / restore database                                │
│                                                                          │
│ Numbered test lanes (tests/t*.sh, t00-t16)                               │
├──────────────────────────────────────────────────────────────────────────┤
│ t00          code-quality analyzers                                      │
│ t01          antivirus (ClamAV)                                          │
│ t02          dependency + Postgres + Teller API freshness                │
│ t03          static security (SAST)                                      │
│ t04          requirements traceability                                   │
│ t05          deploy database verification                                │
│ t06-t08, t10 unit-test lanes (SQL / shell / Python / Swift)              │
│ t09          mutation testing                                            │
│ t11          property + stateful fuzz                                    │
│ t12          dynamic security (DAST, ZAP)                                │
│ t13          Teller API smoke                                            │
│ t14-t15      macOS UI regression + crash verify                          │
│ t16          classification persistence E2E                              │
└──────────────────────────────────────────────────────────────────────────┘


TESTING STACK
=============

  Shell lane      : bats            (tests/sh)
  Python lane     : unittest        (tests/py)
  SQL lane        : pgTAP/pg_prove  (tests/sql)
  Swift lane      : swift test      (src/macos-ui/Tests)
  macOS UI lane   : snapshot + XCUITest


SECURITY STACK
==============

  SAST: semgrep, bandit, pip-audit, detect-secrets, gitleaks, shellcheck, swiftlint
  DAST: schemathesis, OWASP ZAP
  AV  : ClamAV

SECURITY SCORECARD (10/10 EXIT GATE)
=====================================

- Authentication boundary: all classifier `/v1/*` routes require `X-Teller-Write-Token` (resolved from `1psa`).
- Transport defaults: classifier API defaults to HTTPS localhost and refuses non-local bind unless explicitly overridden.
- SAST coverage: Semgrep, Bandit (scoped to `src/teller`, `tests/py`, and core entry scripts), pip-audit, detect-secrets, gitleaks, ShellCheck, SwiftLint.
- DAST coverage: Schemathesis (`SCHEMATHESIS_MODE=all` by default) plus ZAP quick scan with machine-readable severity summary.
- ZAP gate policy: threshold-driven fail behavior via `SECURITY_ZAP_FAIL_THRESHOLD` (`high` default; `none|high|medium|low|informational`).
- Local gate enforcement: static SAST gate via `tests/t03_run_static_security_tests.sh`; dynamic DAST gate via `tests/t12_run_dynamic_security_tests.sh` (no GitHub Actions workflows).
- Dependency hygiene: `03_prepare_supply_chain_integrity.sh` compiles hash-pinned lockfiles from `requirements.in` and `requirements/security/requirements-security.in`; install paths consume the compiled lockfiles (`requirements.txt`, `requirements/security/requirements-security.txt`) with hash verification.

SECURITY RUNBOOK (LOCAL COMPROMISE RESPONSE)
============================================

1. Rotate `TELLER_CLASSIFIER_WRITE_TOKEN` in 1psa and restart classifier services.
2. Rotate Teller dashboard credentials/tokens in `~/.teller` contexts as needed.
3. Re-run `tests/t12_run_dynamic_security_tests.sh` and `tests/t03_run_static_security_tests.sh`.
4. Confirm clean artifacts under `artifacts/security` and `artifacts/security-dast`.
5. Require green local security lanes (`t03` static, `t12` dynamic) before merging any recovery changes.


HIGH-LEVEL FLOW
===============

  Teller API --> Python ingest/backfill --> PostgreSQL <--> FastAPI classification API <--> SwiftUI macOS app
                           ^                      ^
                           |                      |
                        1psa secrets         SQL schema + tests


INGEST + NORMALIZATION + PERSISTENCE (SCRIPT 06)
================================================

[scheduler/manual]
      |
      v
07_fetch_teller_api_data.py
      |
      +--> fetch institutions/accounts/transactions
      +--> normalize/transform (pagination + duplicate transaction canonicalization)
      +--> upsert via SQLAlchemy helper layer (persist_all)
      |      - conflict-aware upserts on stable IDs
      |      - stale pending reconciliation + orphan relation pruning
      |      - single commit boundary for atomic persistence
      v
PostgreSQL (teller schema)
      |
      +--> views/triggers/audit paths
```

## Teller Internal Architecture

### 1) AUTH + TOKEN LIFECYCLE (CONNECT -> STORAGE -> API USAGE)

Why: Clarifies security boundaries and where credentials/tokens live and rotate.

```text
Trust boundaries:
- Local app boundary: macOS SwiftUI app + WKWebView connect surface.
- Local secret-at-rest boundary: ~/.teller (0700 dir, 0400 secret files).
- External API boundary: api.teller.io (mTLS + token auth).

┌────────────────────────────────────────────────────────────────────────────────────┐
│                          Local host (macOS machine)                                │
│                                                                                    │
│  1) Connect session bootstrap                                                      │
│  ┌──────────────────────────────────┐       app_id + env + optional enrollment_id  │
│  │ SwiftUI app (ConnectViewModel)   │-------------------------------------------┐  │
│  │ ConnectAPIClient.startSession    │                                           │  │
│  └──────────────────────────────────┘                                           │  │
│                                                                                 v  │
│  ┌─────────────────────────────────────────────────────────┐  callback(token, id)  │
│  │ Teller Connect JS in WKWebView (ConnectWebFlowView)     │--------------------┐  │
│  └─────────────────────────────────────────────────────────┘                    │  │
│                                                                                 |  │
│  2) Token/enrollment persistence                                                v  │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │ ~/.teller/                                                                   │  │
│  │ - auth_token.json + enrollment_id.txt (default context)                      │  │
│  │ - auth_token_<suffix>.json + enrollment_id_<suffix>.txt (Add contexts)       │  │
│  │ - certificate.pem + private_key.pem + application_id.txt                     │  │
│  │ - perms: directory 0700, secret files 0400                                   │  │
│  └───────────────────────────────┬──────────────────────────────────────────────┘  │
│                                  │ read contexts + cert/key + token                │
│                                  v                                                 │
│  3) API usage path                                                 4) disconnected │
│  ┌──────────────────────────────────────────────────────────────┐     enrollment   │
│  │ 07_fetch_teller_api_data.py                                  │                  │
│  │ - builds contexts from default/suffix/metadata files         │-----repair---┐   │
│  │ - sends cert/key (mTLS) + token (basic user token:blank)     │              │   │
│  │ - retries once after local repair workflow                   │              │   │
│  └───────────────────────────────┬──────────────────────────────┘              │   │
└──────────────────────────────────┼─────────────────────────────────────────────┼───┘
                                   │                                             │
                                   v                                             │
                         ┌───────────────────────────────┐                       │
                         │ api.teller.io                 │                       │
                         │ /institutions, /accounts, ... │                       │
                         └───────────────┬───────────────┘                       │
                                         │ enrollment.disconnected               │
                                         └───────────────────────────────────────┘
                                                        launches 10_run_classification_macos_ui.sh
```

Token and credential lifecycle notes:

- Initial connect/add: token returned by Connect is written to `auth_token*.json`; enrollment id is written to matching `enrollment_id*.txt`.
- Reconnect/rotate token: reconnect action updates the selected existing context files in place.
- Multi-context support: add action allocates unique suffixed file pairs so multiple enrollments can coexist.
- Runtime consumption: `07_fetch_teller_api_data.py` reads local contexts, then calls Teller with local cert/key plus per-context token.
- Disconnected enrollment recovery: when Teller returns `enrollment.disconnected`, script triggers the macOS Connect repair flow and retries once.
- Cert/key rotation boundary: certificate/private key issuance and revocation happen in Teller dashboard; local app/scripts only read local `certificate.pem` / `private_key.pem`.

### 2) INGEST + NORMALIZATION + PERSISTENCE SEQUENCE

Why: Shows exact order and idempotency points for data movement into Postgres.

```text
[scheduler/manual]
      |
      v
07_fetch_teller_api_data.py
      |
      +--> fetch institutions/accounts/transactions
      |
      +--> normalize/transform
      |
      +--> upsert via SQLAlchemy
      |
      v
PostgreSQL (teller schema)
      |
      +--> views/triggers/audit paths
```

### 3) DATA MODEL ER DIAGRAM (CORE TABLES + RELATIONSHIPS)

Why: Repo has rich SQL under `src/sql/postgres/`; a compact ER view speeds onboarding.

```text
Legend:
- [W] write-heavy (ingest/classification frequently mutates rows)
- [R] read-heavy  (primarily lookup/query workload)
- [M] mixed
- PK/FK only shown in each box

┌──────────────────────────────────────────────────────────────┐
│ teller.institution [R]                                       │
│ PK institution_id                                            │
└──────────────────────────────────────────────────────────────┘
                         ^
                         | FK account.institution_id
┌──────────────────────────────────────────────────────────────┐
│ teller.account [W]                                           │
│ PK account_id                                                │
│ FK institution_id -> institution.id                          │
│ enrollment_id (logical; no local FK)                         │
└──────────────────────────────────────────────────────────────┘
                         ^
                         | FK transaction.account_id
┌──────────────────────────────────────────────────────────────┐
│ teller.transaction [W]                                       │
│ PK transaction_id                                            │
│ FK account_id -> account.id                                  │
└──────────────────────────────────────────────────────────────┘

Classification branch (child -> parent):

┌──────────────────────────────────────────────────────────────┐
│ teller.transaction_nys_snw_category [W]                      │
│ PK/FK transaction_id -> transaction.id                       │
│ FK nys_snw_category_id -> nys_snw_category.id                │
└──────────────────────────────────────────────────────────────┘
            parents:
            - transaction.transaction_id
            - nys_snw_category.nys_snw_category_id

┌───────────────────────────────┐
│ teller.nys_snw_category [R]   │
│ PK nys_snw_category_id        │
└───────────────────────────────┘

Matchy branch (child -> parent):

┌──────────────────────────────────────────────────────────────┐
│ teller.transaction_email_match_run [W]                       │
│ PK match_run_id                                              │
│ FK transaction_id -> transaction.id                          │
└──────────────────────────────────────────────────────────────┘
                         ^
                         | FK transaction_email_candidate.match_run_id
┌──────────────────────────────────────────────────────────────┐
│ teller.transaction_email_candidate [W]                       │
│ PK candidate_id                                              │
│ FK match_run_id -> transaction_email_match_run.id            │
│ FK transaction_id -> transaction.id                          │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ teller.transaction_email_match [W]                           │
│ PK match_id                                                  │
│ FK transaction_id -> transaction.id                          │
└──────────────────────────────────────────────────────────────┘
                         ^
                         | FK transaction_email_match_audit.match_id
┌──────────────────────────────────────────────────────────────┐
│ teller.transaction_email_match_audit [W]                     │
│ PK match_audit_id                                            │
│ FK match_id -> transaction_email_match.id                    │
└──────────────────────────────────────────────────────────────┘
```

FK direction map (child -> parent):

- `account.institution_id -> institution.institution_id`
- `transaction.account_id -> account.account_id`
- `transaction_nys_snw_category.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_nys_snw_category.nys_snw_category_id -> nys_snw_category.nys_snw_category_id`
- `transaction_email_match_run.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_email_candidate.match_run_id -> transaction_email_match_run.match_run_id` (ON DELETE CASCADE)
- `transaction_email_candidate.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_email_match.transaction_id -> transaction.transaction_id` (ON DELETE CASCADE)
- `transaction_email_match_audit.match_id -> transaction_email_match.match_id` (ON DELETE CASCADE)

Notes:

- `enrollment` is currently modeled as `account.enrollment_id` (no `teller.enrollment` table in `src/sql/postgres/`).
- `transaction_classification` is implemented as `teller.transaction_nys_snw_category`.
- Matchy tables (`transaction_email_match_run`, `transaction_email_candidate`, `transaction_email_match`, `transaction_email_match_audit`) are in active use by the classification API.

### 4) LOCAL RUNTIME TOPOLOGY (PROCESSES, PORTS, FILES, ENV)

Why: Helpful for debugging "what should be running" and "where config comes from".

```text
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   Local machine (macOS)                                    │
│                                                                                            │
│  App/UI process                                                                            │
│  ┌──────────────────────────────────────────────────────────┐                              │
│  │ SwiftUI app: TransactionClassifier                       │                              │
│  │ launcher: 10_run_classification_macos_ui.sh              │                              │
│  │ Connect runs in-process (no localhost Connect server)    │                              │
│  └───────────────────────────────┬──────────────────────────┘                              │
│                                  │ HTTPS: TELLER_CLASSIFIER_API_URL                        │
│                                  │ default https://127.0.0.1:8787                          │
│                                  v                                                         │
│  API process                     ┌───────────────────────────────────────────────────────┐ │
│  ┌───────────────────────────────│ FastAPI: 09_run_classification_api.py                 │ │
│  │                               │ bind env: TELLER_CLASSIFIER_API_HOST/PORT             │ │
│  │                               │ defaults: 127.0.0.1:8787                              │ │
│  │                               │ startup gate: requires 1psa item                      │ │
│  │                               │ TELLER_CLASSIFIER_WRITE_TOKEN                         │ │
│  │                               └───────────────────────┬───────────────────────────────┘ │
│  │                                                       │ SQLAlchemy                      │
│  │                                                       v                                 │
│  │                                 ┌─────────────────────────────────────────────────────┐ │
│  │                                 │ PostgreSQL (profile-resolved)                       │ │
│  │                                 │ typical local target: localhost:5432                │ │
│  │                                 │ selected via TELLER_DB_PROFILE / profile file       │ │
│  │                                 └─────────────────────────────────────────────────────┘ │
│  │                                                                                         │
│  │ optional Mailcart integration                                                           │
│  └──────────────────────────────────────► https://127.0.0.1:8788 (default)                 │
│                                         env: MAILCART_SERVICE_BASE_URL / TOKEN             │
│                                                                                            │
│  File/config + secret sources                                                              │
│  - ~/.teller/auth_token*.json, enrollment_id*.txt, certificate.pem, private_key.pem        │
│  - DB profile file search: ~/.teller/db_profiles.json → ./config/db-profiles.local.json →  │
│    ./config/db-profiles.json (or TELLER_DB_PROFILE_FILE override)                          │
│  - ~/.env (loaded by ingest/profile fallback paths for ITEM.field entries)                 │
│  - Secret authority: 1psa (classifier write token + DB connection fields/password)         │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

Local runtime debugging checklist:

- If UI cannot load data, verify FastAPI is listening on `127.0.0.1:8787` (or your `TELLER_CLASSIFIER_API_URL` override).
- If write endpoints fail at startup, verify `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN` returns a non-empty value.
- If DB connect fails, inspect the resolved profile (`TELLER_DB_PROFILE`, profile file path precedence, `1psa_or_env_item`, and `DB_DIALECT`/`SQLITE_PATH` exports; sqlite default path is `.database/teller.sqlite3`).
- If match-review email fetch fails, verify optional Mailcart process on `127.0.0.1:8788` or override `MAILCART_SERVICE_BASE_URL`.

### 5) TEST STRATEGY MAP (LANES -> SCOPE -> GATES)

Why: Explains why there are many numbered scripts and what each gate protects.

Gate map (left = execution lane, right = protection intent):

- 01-05 setup/deploy scripts        -> env/bootstrap/deploy preconditions before deeper validation
- t00 code quality                  -> dead code (Vulture/Periphery) + complexity (Radon/Xenon, Lizard)
- t01 antivirus                     -> ClamAV signature freshness + repo scan
- t02 dependency freshness          -> Python deps + Postgres + Teller API version drift
- t03 static security (SAST)        -> Semgrep, Bandit, pip-audit, detect-secrets, gitleaks, ShellCheck, SwiftLint
- t04 requirements traceability     -> `#R...` tag <-> requirements doc mapping
- t05 deploy database verification  -> schema/role/constraint invariants on the deployed DB
- t06 sql unit tests                -> pgTAP schema/contract checks
- t07 shell unit tests              -> bats coverage of script flags/outputs/failure semantics
- t08 python unit tests             -> package/unit behavior for Python ingestion/API helpers
- t09 mutation testing              -> mutmut score + coverage gate
- t10 swift unit tests              -> macOS client unit behavior
- t11 fuzz                          -> Hypothesis property + stateful fuzz with budget gating
- t12 dynamic security (DAST)       -> Schemathesis + ZAP runtime probes
- t13 Teller API smoke              -> external API assumptions + minimal end-to-end liveliness
- t14 macOS UI regression           -> snapshot + XCUITest flow stability
- t15 macOS crash verify            -> crash reporter path + recovery metadata
- t16 classification persistence    -> API -> DB write/read correctness
- 10 parallel runner                -> aggregate readiness signal across the t00-t16 gates

How to interpret failures:

- 01-05 fail: stop early; developer/runtime prerequisites are not trustworthy yet.
- t00-t04 fail: code quality / freshness / security / traceability hygiene regression.
- t05-t08, t10 fail: lane-specific regression in SQL/shell/python/swift unit behavior.
- t09 fail: mutation score regression — review surviving mutants.
- t11 fail: property/stateful fuzz found a counterexample; capture the example and add a unit test.
- t12 fail: potential exploitable runtime behavior; treat as security triage.
- t13 fail: likely upstream/external contract drift or availability issue.
- t14-t15 fail: macOS UI regression or crash-handling path break.
- t16 fail: persistence contract break between API and database layers.
- 10 (parallel runner) fail: composite readiness not met; inspect failing child lanes.

### 6) SECURITY THREAT MODEL (TRUST BOUNDARIES + DATA FLOWS)

Why: Security tools are present, but a visual threat model explains risk ownership.

```text
Trust boundaries:
- B1 local host boundary (developer macOS runtime)
- B2 external API boundary (Teller api.teller.io)
- B3 secrets boundary (1psa process + ~/.teller secret files)
- B4 DB boundary (PostgreSQL role/session + teller schema)

Legend:
- [TB] trust-boundary crossing
- [AS] attack-surface node

                                       [B2 external API boundary]
                                ┌──────────────────────────────────────┐
                                │ Teller API (mTLS + token auth)       │
                                │ - /institutions /accounts /identity  │
                                └───────────────────┬──────────────────┘
                                                    │
                                                    │ F4 response data
                                                    │ + disconnection signals [TB]
                                                    v
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│ [B1 local host boundary]                                                                      │
│                                                                                               │
│  [AS] WKWebView Connect surface                                                               │
│  ┌────────────────────────────────┐                                                           │
│  │ SwiftUI + Connect JS bridge    │---- F1 app/env/enrollment context [TB]                    │
│  │ (connect callbacks, deep links)│                                                           │
│  └──────────────┬─────────────────┘                                                           │
│                 │ F2 token + enrollment_id callback [TB]                                      │
│                 v                                                                             │
│  [B3 secrets boundary]                 [AS] shell/python execution path                       │
│  ┌────────────────────────────────┐     ┌────────────────────────────────────────────────┐    │
│  │ 1psa CLI + ~/.teller files     │<--->│ runtime entrypoints                            │    │
│  │ cert/key/auth_token/enrollment │ F3  │ 07_fetch / 09_run_api / tests/t13_smoke / 08_* │    │
│  └──────────────┬─────────────────┘     └───────────────────────────────┬────────────────┘    │
│                 │ F5 token/cert/key reads [TB]                          | F6 SQL writes/reads |
│                 │ (/v1/* auth gate; /health open)                       |        [TB]         │
│                 v                                                       |                     │
│      FastAPI auth gate + runtime secret checks                          │                     │
│                                                                         |                     │
│                                                                         |                     │
│                                                [B4 DB boundary]         v                     │
│                                          ┌──────────────────────────────────────┐             │
│                                          │ PostgreSQL (teller schema)           │             │
│                                          │ roles, grants, triggers, audit paths │             │
│                                          └──────────────────────────────────────┘             │
│                                                                                               │
│  [AS] FastAPI endpoints:                                                                      │
│  - local classification API routes (/health, /v1/*, /v1/matchy/*)                             │
│  - key risk classes: authz bypass, injection, unsafe deserialization, over-broad CORS         │
│                                                                                               │
│  [AS] dependency/toolchain supply chain:                                                      │
│  - pip + brew + security scanner binaries + cloned helper repos                               │
│  - key risk classes: poisoned package, malicious transitive dependency, tampered tool binary  │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

Primary data flows and ownership:

- F1 Connect bootstrap request (owner: macOS UI): send app/environment/enrollment context into WKWebView Connect session.
- F2 Connect callback secrets (owner: macOS UI + setup service): receive token/enrollment_id and persist into `~/.teller` with restrictive file permissions.
- F3 Secret retrieval for runtime (owner: shell/python runtime): runtime entrypoints (`07_fetch_teller_api_data.py`, `09_run_classification_api.py`, `tests/t13_run_teller_api_smoke_tests.sh`, optional `08_backfill_bank_statements.py`) resolve write token from `1psa` and Teller API cert/key/token from `~/.teller`.
- F4 Teller API exchange (owner: ingest runtime): outbound mTLS + token-auth requests and inbound institution/account/transaction payloads.
- F5 Local API auth gate (owner: FastAPI): require `X-Teller-Write-Token` backed by `1psa` item resolution for `/v1/*` reads and writes (`/health` remains unauthenticated).
- F6 Persistence path (owner: DB + API/ingest): validated SQLAlchemy reads/writes into `teller` schema under least-privilege role assumptions.

Threat ownership map (who mitigates what):

- Local host compromise (B1): repository owners enforce script hygiene, path validation, and explicit command dependencies.
- Secret exfiltration (B3): setup/runtime owners enforce `~/.teller` permission model, narrow secret file set, and `1psa`-only token source for mutations.
- External API contract abuse (B2): ingest/connect owners enforce mTLS + token usage and controlled retry/reconnect behavior.
- DB integrity escalation (B4): schema/API owners enforce authz on `/v1/*` endpoints, parameterized ORM usage, and verification/audit tests.
- Supply-chain compromise (AS): platform owners enforce freshness/security lanes (`tests/t02`, `tests/t03`, `tests/t12`) and fail-gates on high/critical findings.

Accepted residual risk (owner: repository owner): the `/v1/*` auth gate uses a single shared `X-Teller-Write-Token` with no per-user identity or roles; reads and writes resolve to the same credential. This coarse model is an intentional, scoped decision for the single-user local threat model and must be upgraded to per-user identity, a distinct read-only token, and DB reader/writer role mapping if the service becomes multi-user, is exposed beyond localhost, or is deployed to a shared environment. See [`docs/security/api_authorization_model.md`](docs/security/api_authorization_model.md).

### 7) OPERATIONS / RECOVERY FLOW (BACKUP, RESTORE, DESTROY)

Why: Scripts `97/98/99` are critical but easy to misuse without a flow diagram.

```text
Normal operations running
      |
      v
Run 97_backup_database.sh
      |
      +--> profile selection (via db_profile_export.sh):
      |      TELLER_DB_PROFILE env override -> else db_profiles default_profile
      |
      +--> if local target:
      |      pg_dump via postgres admin (POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD via 1psa)
      |      writes <profile>_<db>_<timestamp>.dump + matching _globals.sql
      |
      +--> if managed target:
      |      re-resolves via supabase_direct profile
      |      schema-scoped pg_dump using PG_ONEPSA_ITEM via 1psa (or TELLER_DB_PASSWORD)
      |      writes <profile>_<db>_<timestamp>.dump (no globals; managed targets
      |      do not expose role/grant state)
      |
      v
Verify backup artifacts exist and are readable
      |
      +--> if missing/corrupt: STOP and re-run 97
      |
      v
[Optional destructive step?]
      |
      +--> no  -> skip to restore preflight
      |
      +--> yes -> Run 98_destroy_database.sh
      |          |
      |          +--> profile selection (via db_profile_export.sh):
      |          |      TELLER_DB_PROFILE env override
      |          |      -> else db_profiles default_profile
      |          |      -> target local vs managed
      |          |
      |          +--> if managed target:
      |          |      destroy schema + roles (not DROP DATABASE)
      |          |      credential resolution: env override -> PG_ONEPSA_ITEM via 1psa
      |          |
      |          +--> if local target:
      |          |      destroy database + teller user/roles
      |          |      password resolution: POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD via 1psa
      |          |
      |          +--> requires explicit "destroy" confirmation
      |
      v
Run 99_restore_database.sh
      |
      +--> profile selection (via db_profile_export.sh):
      |      TELLER_DB_PROFILE env override -> else db_profiles default_profile
      |
      +--> if managed target:
      |      full restore is REFUSED (cannot CREATE DATABASE / restore globals)
      |      require --table schema.table_name for scoped restore
      |      managed --table restore uses PG_ONEPSA_ITEM via 1psa (or TELLER_DB_PASSWORD)
      |
      +--> if local target:
      |      restore credential resolution order:
      |        1) POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD (admin restore actions)
      |        2) TELLER_PSA_ITEM/TELLER_PSA_FIELD (post-restore teller login reset/verification)
      |
      |      schema exists? (full restore mode)
      |        - yes and no --table: refuse restore (safety stop)
      |        - no: continue full restore
      |        - scoped --table restore: allowed into existing schema
      |
      |      full restore order:
      |        restore matching globals first -> restore dump with --create
      |        -> ALTER USER teller to current 1psa secret
      |        -> verify teller can authenticate
      |
      v
Post-restore verification
      |
      +--> ./tests/t05_deploy_database_verification_test.sh
      +--> ./tests/t16_classification_persistence_verification_test.sh
```

Operational notes:

- Treat `97` as mandatory before any destructive `98` action.
- For local-target restores, `99` requires a matching `_globals.sql` companion file in full-restore mode.
- For managed-target restores, `99` always requires `--table schema.table` (full restore is refused because
  managed targets cannot accept a CREATE-DATABASE-style restore or replay globals).
- Use `--table schema.table` in `99` for targeted repair when full schema replacement is not desired.

## Teller-Owned Algorithm: OCR Statement-Line Reconstruction

The match pipeline and the OCR statement-backfill lean on a handful of classic computer-science algorithms.
Teller owns one of them; the others live with their owning repos:

| Algorithm | Job in the pipeline | Module | Code (file → symbols) | Requirement |
| --- | --- | --- | --- | --- |
| TF-IDF / Okapi BM25 | Rank candidate emails by how well their text matches a transaction | matchy | see [`../matchy/README.md`](../matchy/README.md) | R042–R044, R047 |
| Subset-sum reconciliation | Detect when receipt line-items add up to the bank's single total | matchy | see [`../matchy/README.md`](../matchy/README.md) | R045, R047 |
| SimHash + Hamming distance | Collapse near-duplicate emails (forwards / marketing copies) | matchy | see [`../matchy/README.md`](../matchy/README.md) | R055 |
| Aho-Corasick | Match many search filters against each email field in one pass | mailcart | see [`../mailcart/README.md`](../mailcart/README.md) | R050 |
| 1-D density clustering | Rebuild text lines from scattered OCR word boxes | teller | `08_backfill_bank_statements.py` → `reconstruct_lines`, `_adaptive_line_epsilon` | R030 |

### 1-D density clustering — rebuilding OCR text lines

**The idea (plain English):** OCR returns word boxes with (x, y) positions but no concept of
"lines." Words on the same visual line share a similar `y`. We sort top-to-bottom and start
a new line wherever the vertical gap is unusually large. A *fixed* gap threshold breaks
across font sizes and scan resolutions, so we derive the threshold from the **median** gap
(robust to outliers) — adaptive density-based clustering in one dimension.

```text
y positions (sorted): .12 .13 .14    .31 .32      .55
consecutive gaps:        .01 .01   .17    .01    .23
epsilon = max(floor, gap_factor · median(gaps))
split wherever gap > epsilon:
   line 1 [.12 .13 .14]   line 2 [.31 .32]   line 3 [.55]
```

**Where it lives:** `teller/08_backfill_bank_statements.py` (`reconstruct_lines`,
`_adaptive_line_epsilon`). Requirement R030.

**Read more:** [Cluster analysis](https://en.wikipedia.org/wiki/Cluster_analysis) ·
[Single-linkage clustering](https://en.wikipedia.org/wiki/Single-linkage_clustering) ·
[Median](https://en.wikipedia.org/wiki/Median)
