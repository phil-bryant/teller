# Architecture

This document contains architecture-focused reference material moved from `README.md`.

## GLOBAL ARCHITECTURE: TELLER → MATCHY ← MAILCART

Implemented in this repository: Teller ingest + schema + classification API + macOS review app.
External ecosystem services: Matchy worker/orchestration and Mailcart Outlook/Graph adapter.

```text
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                          SYSTEM LANDSCAPE                                         │
│                                                                                                   │
│  ┌────────────────────────────────┐    HTTP (search/move)     ┌────────────────────────────────┐  │
│  │             MATCHY             │ ────────────────────────► │            MAILCART            │  │
│  │                                │ ◄──────────────────────── │                                │  │
│  │ - FastAPI service              │      message candidates   │ - Outlook/Graph integration    │  │
│  │ - Runs transaction↔email match │                           │ - Search endpoint for emails   │  │
│  │ - Combines scoring + AI ranker │                           │ - Move endpoint to folder      │  │
│  │ - Writes run/candidate/match   │                           │   `matchy`                     │  │
│  │   records to Teller DB         │                           └────────────────────────────────┘  │
│  └───────────────┬────────────────┘                                                               │
│                  │ SQL read/write                                                                 │
│                  ▼                                                                                │
│  ┌──────────────────────────────────────────────────────────┐                                     │
│  │                      TELLER DB                           │                                     │
│  │                                                          │                                     │
│  │ - Source transactions: `teller.transaction`              │                                     │
│  │ - Match run table: `teller.transaction_email_match_run`  │                                     │
│  │ - Candidates table: `teller.transaction_email_candidate` │                                     │
│  │ - Match table: `teller.transaction_email_match`          │                                     │
│  └──────────────────────────────────────────────────────────┘                                     │
│                                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘

TRIGGER FLOW
┌─────────────────────────────┐      POST /v1/matchy/runs       ┌────────────────────────────┐
│ Caller (manual/auto/retry)  │───────────────────────────────► │ Matchy API                 │
│ (operator/job in ecosystem) │                                 │ validates ids + starts run │
└─────────────────────────────┘                                 └────────────────────────────┘
```

### Additional Architecture Views

#### Auth + Token Lifecycle (Connect -> storage -> API usage)

```text
Trust boundaries:
- Local app boundary: macOS SwiftUI app + WKWebView connect surface
- Local secrets-at-rest boundary: ~/.teller (0700 dir, 0400 secret files)
- External API boundary: api.teller.io (mTLS + token auth)

SwiftUI Connect flow
  -> receives token/enrollment callback
  -> writes auth_token*.json + enrollment_id*.txt under ~/.teller
  -> ingest/runtime reads cert/key + per-context token
  -> calls api.teller.io endpoints
  -> on enrollment.disconnected, launch local repair flow and retry once
```

Token lifecycle notes:

- Initial connect/add writes token and enrollment ID files to `~/.teller`.
- Reconnect rotates token in-place for the selected context.
- Multi-context enrollments use suffixed file pairs (`auth_token_<suffix>.json`, `enrollment_id_<suffix>.txt`).
- Certificate/private key rotation remains managed in Teller Dashboard; local scripts only consume local files.

#### Classification Write Path + AuthZ Boundary

```text
macOS UI action
  -> POST /v1/transactions/classifications
  -> FastAPI app startup resolves TELLER_CLASSIFIER_WRITE_TOKEN from 1psa
  -> shared auth guard enforces X-Teller-Write-Token on all /v1 routes
  -> Pydantic validates payload
  -> SQLAlchemy persists to teller.transaction_nys_snw_category
  -> 21_classification_persistence_verification_test.sh confirms API->DB write/read
```

#### Local Runtime Topology (processes, ports, configs)

```text
TransactionClassifier (SwiftUI app, launched by 09_run_classification_macos_ui.sh)
  -> talks to FastAPI at TELLER_CLASSIFIER_API_URL (default https://127.0.0.1:8787)

08_run_classification_api.py (FastAPI)
  -> binds TELLER_CLASSIFIER_API_HOST/PORT (default 127.0.0.1:8787)
  -> requires 1psa-backed TELLER_CLASSIFIER_WRITE_TOKEN before serving
  -> defaults to HTTPS with local cert/key (explicit HTTP override only via TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP=true)
  -> persists via SQLAlchemy to profile-resolved PostgreSQL target

Optional Mailcart proxy target defaults to http://127.0.0.1:8788
  (override with MAILCART_SERVICE_BASE_URL / MAILCART_SERVICE_TOKEN)

Config and secrets:
  - ~/.teller/auth_token*.json, enrollment_id*.txt, certificate.pem, private_key.pem
  - db profile resolution: ~/.teller/db_profiles.json -> ./config/db-profiles.local.json -> ./config/db-profiles.json
  - ~/.env fallbacks for ITEM.field profile entries
```

### Teller ↔ Mailcart contract (Match Review UI)

The Teller classifier API proxies Mailcart for the macOS Match Review three-pane UI. The
contract Mailcart exposes (see `mailcart/scripts/matchy_mailcart_api.py` and matchy's
`matchy/mailcart_client.py`):

- `GET /v1/messages/search?query=<string>&limit=<int>` — returns
`{"messages": [{"message_id", "subject", "preview", "received_at", "sender", "body_text"}]}`.
- `GET /v1/messages/{message_id}` — returns
`{"message_id", "subject", "preview", "received_at", "sender", "recipients", "html_body", "text_body", "body_text"}`.
- `POST /v1/messages/{message_id}/move` — used by matchy, not by Teller.

Teller calls Mailcart via the proxy module `src/teller/teller_mailcart_client.py`:

- Base URL defaults to `http://127.0.0.1:8788` (Mailcart is a local-only service); override
with the `MAILCART_SERVICE_BASE_URL` environment variable (the same name matchy uses).
- Bearer token is optional and read from `MAILCART_SERVICE_TOKEN`; it is only attached when
set. Mailcart does not validate it. The Microsoft Graph token Mailcart uses internally is
managed by Mailcart itself (cached at `~/.cache/mailcart/graph_oauth.json`, refreshed on 401).
- Teller exposes three read-only proxy/aggregation endpoints (write token required, like all `/v1/*` routes):
`GET /v1/matchy/transactions/{transaction_id}/candidates`,
`GET /v1/matchy/messages/{email_message_id}`,
`GET /v1/matchy/messages/search`. Each endpoint maps Mailcart's
`{message_id, sender, preview, body_text}` fields onto the UI-facing
`{email_message_id, from, snippet, html_body, text_body}` shape used by `MatchCandidateRow`,
`EmailMessage`, and `EmailSearchHit`.
- Per-id Mailcart failures during candidate enrichment degrade gracefully — the row returns
with `mailcart_error` rather than failing the whole listing — so the review pane remains
usable when Mailcart is partially unavailable.

## Teller Technology Stack

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
 │   - Ingest: 18_fetch_teller_api_data.py                                      │
 │   - Backfill: 19_backfill_bank_statements.py                                 │
 │   - API: 08_run_classification_api.py ->                                     │
 │          src/teller/teller_classification_api.py                             │
 └───────────────────────────────────────┬──────────────────────────────────────┘
                                         |
                                         v
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                            DATA / PERSISTENCE LAYER                          │
 ├──────────────────────────────────────────────────────────────────────────────┤
 │ PostgreSQL (local profile or managed profile via db profiles)                │
 │ Schema + SQL objects in: src/sql/postgres/                                   │
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
│ 01-03 setup (prereqs, venv, dependencies)                                │
│ 04-06 quality/security prereqs (freshness, AV, SAST)                     │
│ 07-08 DB deploy + verification                                           │
│ 09-13 unit/regression test lanes                                         │
│ 14-21 integration, API smoke, crash verification, app run                │
│ 22 parallel aggregate runner                                             │
│ 97-99 backup / destroy / restore database                                │
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
- CI enforcement: required PR security workflow at `.github/workflows/security-pr.yml`; scheduled deep security workflow at `.github/workflows/security-nightly.yml`.
- Dependency hygiene: `requirements.txt` is pinned for runtime dependencies (including `psycopg2-binary==2.9.12`), with a bounded compatibility range for test tooling (`pytest>=8.1,<10`).

SECURITY RUNBOOK (LOCAL COMPROMISE RESPONSE)
============================================

1. Rotate `TELLER_CLASSIFIER_WRITE_TOKEN` in 1psa and restart classifier services.
2. Rotate Teller dashboard credentials/tokens in `~/.teller` contexts as needed.
3. Re-run `22_run_dynamic_security_tests.sh` and `06_run_static_security_tests.sh`.
4. Confirm clean artifacts under `artifacts/security` and `artifacts/security-dast`.
5. Require green CI (`security-pr`) before merging any recovery changes.


HIGH-LEVEL FLOW
===============

  Teller API --> Python ingest/backfill --> PostgreSQL <--> FastAPI classification API <--> SwiftUI macOS app
                           ^                      ^
                           |                      |
                        1psa secrets         SQL schema + tests


INGEST + NORMALIZATION + PERSISTENCE (SCRIPT 16)
================================================

[scheduler/manual]
      |
      v
18_fetch_teller_api_data.py
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

```text
1) AUTH + TOKEN LIFECYCLE (CONNECT -> STORAGE -> API USAGE)
------------------------------------------------------------
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
│  │ SwiftUI app (ConnectViewModel)  │ -------------------------------------------┐  │
│  │ ConnectAPIClient.startSession   │                                            │  │
│  └──────────────────────────────────┘                                           │  │
│                                                                                 v  │
│  ┌─────────────────────────────────────────────────────────┐  callback(token, id)  │
│  │ Teller Connect JS in WKWebView (ConnectWebFlowView)    │ --------------------┐  │
│  └─────────────────────────────────────────────────────────┘                    │  │
│                                                                                 v  │
│  2) Token/enrollment persistence                                                   │
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
│  │ 18_fetch_teller_api_data.py                                  │                  │
│  │ - builds contexts from default/suffix/metadata files         │ ----repair---┐   │
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
                                                        launches 09_run_classification_macos_ui.sh
```

Token and credential lifecycle notes:

- Initial connect/add: token returned by Connect is written to `auth_token*.json`; enrollment id is written to matching `enrollment_id*.txt`.
- Reconnect/rotate token: reconnect action updates the selected existing context files in place.
- Multi-context support: add action allocates unique suffixed file pairs so multiple enrollments can coexist.
- Runtime consumption: `18_fetch_teller_api_data.py` reads local contexts, then calls Teller with local cert/key plus per-context token.
- Disconnected enrollment recovery: when Teller returns `enrollment.disconnected`, script triggers the macOS Connect repair flow and retries once.
- Cert/key rotation boundary: certificate/private key issuance and revocation happen in Teller dashboard; local app/scripts only read local `certificate.pem` / `private_key.pem`.

1. INGEST + NORMALIZATION + PERSISTENCE SEQUENCE

---

Why: Shows exact order and idempotency points for data movement into Postgres.

[scheduler/manual]
      |
      v
18_fetch_teller_api_data.py
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

1. CLASSIFICATION WRITE PATH + AUTHZ BOUNDARY

---

Why: Makes mutation protection and persistence verification explicit.

```text
Trust/authz boundaries:
- UI boundary: macOS client invokes localhost FastAPI routes.
- Auth boundary: `/v1/*` routes (reads + writes) require `X-Teller-Write-Token` from 1psa-backed secret.
- Persistence boundary: only validated writes reach Postgres via SQLAlchemy session.

┌────────────────────────────────────────────────────────────────────┐
│ Local host (macOS)                                                 │
│                                                                    │
│ User action in macOS UI (TransactionClassifier/APIClient)          │
│   ├─ GET  /v1/transactions                                         │
│   └─ POST /v1/transactions/classifications                         │
│                     │                                              │
│                     v                                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ FastAPI app (`08_run_classification_api.py` -> `create_app`) │  │
│  │                                                              │  │
│  │ 1) Startup preflight resolves `TELLER_CLASSIFIER_WRITE_TOKEN`│  │
│  │    from 1psa before serving `/v1/*` traffic.                 │  │
│  │ 2) Request authz enforces `X-Teller-Write-Token` on `/v1/*`; │  │
│  │    `/health` remains unauthenticated.                        │  │
│  │ 3) Pydantic validation rejects malformed payloads.           │  │
│  │ 4) `_write_one` persists classification mutations via        │  │
│  │    SQLAlchemy into `teller.transaction_nys_snw_category`.    │  │
│  └───────────────────────────────┬──────────────────────────────┘  │
└──────────────────────────────────┼─────────────────────────────────┘
                                   v
                     ┌────────────────────────────────┐
                     │ PostgreSQL (teller schema)     │
                     │ classification row is persisted│
                     └───────────────┬────────────────┘
                                     │ verified by
                                     v
          `tests/t16_classification_persistence_verification_test.sh`
```

1. DATA MODEL ER DIAGRAM (CORE TABLES + RELATIONSHIPS)

---

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

1. LOCAL RUNTIME TOPOLOGY (PROCESSES, PORTS, FILES, ENV)

---

Why: Helpful for debugging "what should be running" and "where config comes from".

```text
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   Local machine (macOS)                                    │
│                                                                                            │
│  App/UI process                                                                            │
│  ┌──────────────────────────────────────────────────────────┐                              │
│  │ SwiftUI app: TransactionClassifier                       │                              │
│  │ launcher: 09_run_classification_macos_ui.sh              │                              │
│  │ Connect runs in-process (no localhost Connect server)    │                              │
│  └───────────────────────────────┬──────────────────────────┘                              │
│                                  │ HTTP: TELLER_CLASSIFIER_API_URL                         │
│                                  │ default https://127.0.0.1:8787                          │
│                                  v                                                         │
│  API process                     ┌───────────────────────────────────────────────────────┐ │
│  ┌───────────────────────────────│ FastAPI: 08_run_classification_api.py                 │ │
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
│  └──────────────────────────────────────► http://127.0.0.1:8788 (default)                  │
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
- If DB connect fails, inspect the resolved profile (`TELLER_DB_PROFILE`, profile file path precedence, and `1psa_or_env_item`).
- If match-review email fetch fails, verify optional Mailcart process on `127.0.0.1:8788` or override `MAILCART_SERVICE_BASE_URL`.

1. TEST STRATEGY MAP (LANES -> SCOPE -> GATES)

---

Why: Explains why there are many numbered scripts and what each gate protects.

Gate map (left = execution lane, right = protection intent):

- 01-08 setup/deploy checks  -> env/bootstrap/deploy preconditions before deeper validation
- 09 shell tests             -> script behavior/contracts (flags, outputs, failure semantics)
- 10 python tests            -> package/unit behavior for Python ingestion/API helpers
- 11 sql tests               -> schema invariants and DB contract checks (pgTAP)
- 12 swift tests             -> app unit behavior in the macOS client
- 13 ui regression           -> snapshot + XCUITest flow stability
- 14 crash verify            -> crash reporter path and expected crash-handling telemetry
- 15 smoke                   -> external API assumptions and minimal end-to-end liveliness
- 19 persistence e2e         -> API -> DB correctness for write/read persistence paths
- 20 dynamic security        -> runtime attack surface checks (DAST-style probes)
- 22 parallel                -> aggregate readiness signal across gates

How to interpret failures:

- 01-08 fail: stop early; developer/runtime prerequisites are not trustworthy yet.
- 09-14 fail: lane-specific regression in shell/python/sql/swift/ui/crash behavior.
- 15 fail: likely upstream/external contract drift or availability issue.
- 19 fail: persistence contract break between API and database layers.
- 20 fail: potential exploitable runtime behavior; treat as security triage.
- 22 fail: composite readiness not met; inspect failing child lanes.

1. SECURITY THREAT MODEL (TRUST BOUNDARIES + DATA FLOWS)

---

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
│  │ cert/key/auth_token/enrollment │ F3  │ 06_fetch / 08_run_api / tests/t13_smoke / 07_* │    │
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
- F3 Secret retrieval for runtime (owner: shell/python runtime): runtime entrypoints (`06_fetch_teller_api_data.py`, `08_run_classification_api.py`, `tests/t13_run_teller_api_smoke_tests.sh`, optional `07_backfill_bank_statements.py`) resolve write token from `1psa` and Teller API cert/key/token from `~/.teller`.
- F4 Teller API exchange (owner: ingest runtime): outbound mTLS + token-auth requests and inbound institution/account/transaction payloads.
- F5 Local API auth gate (owner: FastAPI): require `X-Teller-Write-Token` backed by `1psa` item resolution for `/v1/*` reads and writes (`/health` remains unauthenticated).
- F6 Persistence path (owner: DB + API/ingest): validated SQLAlchemy reads/writes into `teller` schema under least-privilege role assumptions.

Threat ownership map (who mitigates what):

- Local host compromise (B1): repository owners enforce script hygiene, path validation, and explicit command dependencies.
- Secret exfiltration (B3): setup/runtime owners enforce `~/.teller` permission model, narrow secret file set, and `1psa`-only token source for mutations.
- External API contract abuse (B2): ingest/connect owners enforce mTLS + token usage and controlled retry/reconnect behavior.
- DB integrity escalation (B4): schema/API owners enforce authz on `/v1/*` endpoints, parameterized ORM usage, and verification/audit tests.
- Supply-chain compromise (AS): platform owners enforce freshness/security lanes (`tests/t02`, `tests/t03`, `tests/t12`) and fail-gates on high/critical findings.

1. OPERATIONS / RECOVERY FLOW (BACKUP, RESTORE, DESTROY)

---

Why: Scripts `97/98/99` are critical but easy to misuse without a flow diagram.

```text
Normal operations running
      |
      v
Run 97_backup_database.sh
      |
      +--> Resolves postgres credential via:
      |      POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD (defaults localhost_postgres_postgres/password)
      |      -> writes <db>_<timestamp>.dump + matching _globals.sql
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
      |
      |
      v
Run 99_restore_database.sh
      |
      +--> restore credential resolution order:
      |      1) POSTGRES_PSA_ITEM/POSTGRES_PSA_FIELD (admin restore actions)
      |      2) TELLER_PSA_ITEM/TELLER_PSA_FIELD (post-restore teller login reset/verification)
      |
      +--> schema exists? (full restore mode)
      |      - yes and no --table: refuse restore (safety stop)
      |      - no: continue full restore
      |      - scoped --table restore: allowed into existing schema
      |
      +--> full restore order:
      |      restore matching globals first -> restore dump with --create
      |      -> ALTER USER teller to current 1psa secret
      |      -> verify teller can authenticate
      |
      v
Post-restore verification
      |
      +--> ./08_deploy_database_verification_test.sh
      +--> ./21_classification_persistence_verification_test.sh
```

Operational notes:

- Treat `97` as mandatory before any destructive `98` action.
- `99` requires a matching `_globals.sql` companion file for full restore mode.
- Use `--table schema.table` in `99` for targeted repair when full schema replacement is not desired.

```

```

