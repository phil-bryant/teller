# Transaction Classification API Requirements

## Scope

Applies to `20_run_classification_api.py`.

R001  Statement: Resolve API host and port from environment with local defaults.
Design: Read `TELLER_CLASSIFIER_API_HOST` and `TELLER_CLASSIFIER_API_PORT`; default to `127.0.0.1:8787`, and fail fast on non-local bind hosts unless `TELLER_CLASSIFIER_ALLOW_NON_LOCAL_BIND=true`.
Tests:
- R001-T01: Run without env overrides and verify default bind configuration path is used.

R005  Statement: Start uvicorn with the teller classification ASGI app.
Design: Build app from `create_app()` and pass into `uvicorn.run`.
Tests:
- R005-T01: Run entrypoint and verify `uvicorn.run` receives app instance and resolved bind settings.

R010  Statement: Require classifier write token availability before serving requests.
Design: Resolve write token only via `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN` during startup and fail fast when 1psa is unavailable or token lookup is empty/failing.
Tests:
- R010-T01: Run entrypoint with missing `1psa` and verify startup fails with explicit token-resolution error.
- R010-T02: Stub failed/empty 1psa lookup and verify startup exits before `uvicorn.run`.

R015  Statement: Run HTTPS by default with explicit insecure override.
Design: Default launch uses TLS cert/key files (`TELLER_CLASSIFIER_TLS_CERT_FILE`, `TELLER_CLASSIFIER_TLS_KEY_FILE`) and starts uvicorn in HTTPS mode; missing cert/key fails startup unless `TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP=true`.
Tests:
- R015-T01: Run without TLS files and verify startup fails with explicit HTTPS configuration error.
- R015-T02: Set `TELLER_CLASSIFIER_ALLOW_INSECURE_HTTP=true` and verify HTTP launch path is allowed.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `20_run_classification_api.py`.
- 2026-05-09: Added R010 for mandatory 1psa-backed write-token preflight.
- 2026-05-25: Added local-bind guardrails and HTTPS-by-default startup requirements (R001/R015).
