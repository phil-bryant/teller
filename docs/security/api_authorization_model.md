# API Authorization Model (Current State)

This document defines the current authorization posture for teller-hosted local API routes and the guardrails for acceptable use.

## Scope

- Applies to local API routes served by the classification/runtime API boundary in this repository's architecture model.
- Applies to `/v1/*` and `/v1/matchy/*` routes.
- `/health` remains intentionally unauthenticated for local readiness/liveness checks.

## Current Authorization Contract

- Request authentication uses a shared header token: `X-Teller-Write-Token`.
- The expected token value is resolved from `1psa` (default item: `TELLER_CLASSIFIER_WRITE_TOKEN`).
- Current model uses one shared credential for both read and write API operations.
- Requests without a valid token are denied.

## Intended Threat Model

- Single-user, local-first environment.
- Services are expected to bind to loopback and not be internet exposed.
- Secret material is managed out-of-repo (`1psa`, local secret files under `~/.teller`).

## Residual Risk (Accepted)

- No user identity is represented at the API layer.
- No role separation exists between read and write paths.
- Anyone with token access has full API mutation authority.

This risk is accepted only for the current single-user local threat model.

## Required Upgrade Triggers

The current model is no longer sufficient if any of the following becomes true:

- API is exposed beyond loopback or to shared hosts.
- Multi-user access is introduced.
- Distinct read vs write trust boundaries are required by product or compliance.

## Target Upgrade Direction

- Introduce per-user/service identity at the API layer.
- Split credentials into at least read-only and read-write scopes.
- Map API scopes to least-privilege DB roles (`reader`/`writer`) and enforce consistently.
- Maintain explicit token rotation procedures with service restart/reload behavior documented and tested.
