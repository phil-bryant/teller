# Classifier API Authorization Model (Single-User Local)

This documents the authorization model for the local classifier FastAPI service and records the
coarse single-token design as an intentional, accepted decision for the current threat model.

## Model

- Every `/v1/*` route requires the `X-Teller-Write-Token` header, resolved from `1psa`
  (`TELLER_CLASSIFIER_WRITE_TOKEN`).
- `/health` is intentionally unauthenticated.
- The supplied token is compared against the configured token using constant-time equality
  (`hmac.compare_digest`).
- The resolved token is cached in-process, so rotating the `1psa` value requires a classifier
  process restart.
- Env-token fallback is allowed only when `TELLER_CLASSIFIER_ALLOW_ENV_WRITE_TOKEN=true` is
  explicitly set, for test/dev workflows.

## Read vs Write

There are two guard functions, but they resolve to the same credential today:

| Guard | Routes | Credential |
| --- | --- | --- |
| `_require_authenticated_access` | Read routes (`GET /v1/categories`, `/v1/categories/counts`, `/v1/transactions`, matchy reads) | `X-Teller-Write-Token` |
| `_require_write_access` | Write routes (`POST`/`PUT`/`DELETE` mutations) | `X-Teller-Write-Token` |

`_require_authenticated_access` currently delegates to `_require_write_access` in
[`src/teller/classification/auth.py`](../../src/teller/classification/auth.py). There is no
runtime read/write privilege separation: every `/v1/*` caller presents the identical shared token.
The two function names exist only as a seam where a distinct read-only credential could later plug
in without re-touching every route.

## Accepted Limitation and Rationale

The single shared token provides no per-user identity and no roles. This is accepted because:

- The service is single-user and bound to localhost over HTTPS only.
- The sole client is the macOS UI, which sends the token on every request.
- The secret lives in `1psa`, not in source or config.
- There is no second principal to distinguish, so role granularity would add complexity without
  reducing real risk.

## Relationship to Database Roles

The database layer defines distinct service roles (`teller_api_reader`, `teller_api_writer`,
`teller_ingest_writer`, `teller_migration_admin`; see
[`postgres_access_model.md`](postgres_access_model.md)). The API process uses a single DB identity
and does not map an authenticated API caller onto those roles. Role separation is enforced at the
DB boundary, not per API caller.

## Upgrade Triggers (When This Must Change)

Introduce per-user identity, a distinct read-only token, and map authenticated callers onto the
existing DB reader/writer roles if any of the following becomes true:

- More than one user accesses the service.
- The service is exposed beyond localhost (remote or shared network).
- The service is deployed to a shared/multi-tenant environment.
