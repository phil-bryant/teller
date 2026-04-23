# Transaction Classification API Requirements

## Scope

Applies to `11_transaction_classification_api.py`.

R001  Statement: Resolve API host and port from environment with local defaults.
Design: Read `TELLER_CLASSIFIER_API_HOST` and `TELLER_CLASSIFIER_API_PORT`; default to `127.0.0.1:8787`.
Tests:
- Run without env overrides and verify default bind configuration path is used.

R005  Statement: Start uvicorn with the teller classification ASGI app.
Design: Build app from `create_app()` and pass into `uvicorn.run`.
Tests:
- Run entrypoint and verify `uvicorn.run` receives app instance and resolved bind settings.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `11_transaction_classification_api.py`.
