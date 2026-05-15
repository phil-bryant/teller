# Transaction Classification API Requirements

## Scope

Applies to `14_run_classification_api.py`.

R001  Statement: Resolve API host and port from environment with local defaults.
Design: Read `TELLER_CLASSIFIER_API_HOST` and `TELLER_CLASSIFIER_API_PORT`; default to `127.0.0.1:8787`.
Tests:
- Run without env overrides and verify default bind configuration path is used.

R005  Statement: Start uvicorn with the teller classification ASGI app.
Design: Build app from `create_app()` and pass into `uvicorn.run`.
Tests:
- Run entrypoint and verify `uvicorn.run` receives app instance and resolved bind settings.

R010  Statement: Require classifier write token availability before serving requests.
Design: Resolve write token only via `1psa -p TELLER_CLASSIFIER_WRITE_TOKEN` during startup and fail fast when 1psa is unavailable or token lookup is empty/failing.
Tests:
- Run entrypoint with missing `1psa` and verify startup fails with explicit token-resolution error.
- Stub failed/empty 1psa lookup and verify startup exits before `uvicorn.run`.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `14_run_classification_api.py`.
- 2026-05-09: Added R010 for mandatory 1psa-backed write-token preflight.
