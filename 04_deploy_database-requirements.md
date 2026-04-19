# Deploy Database Requirements

## Scope

Applies to `04_deploy_database.sh`.

R001  Statement: Fail fast when deployment steps fail.
Design: Use `set -e` and exit non-zero on unrecoverable errors.
Tests:
- Force failing SQL execution and verify script exits non-zero.

R005  Statement: Require `1psa` before credential lookup.
Design: Check `1psa` on PATH before password retrieval.
Tests:
- Run without `1psa` and verify clear failure message.

R010  Statement: Resolve postgres admin password from configurable 1psa source.
Design: Use default item/field with override support via environment variables.
Tests:
- Override item/field and verify resolved password path is used.

R015  Statement: Resolve teller database password from configurable 1psa source.
Design: Use default teller item/field with override support via environment variables.
Tests:
- Override teller item/field and verify resolved password path is used.

R020  Statement: Refuse deploy when required passwords resolve empty.
Design: Validate both password variables before SQL steps.
Tests:
- Return empty password from 1psa and verify script exits non-zero.

R025  Statement: Run admin bootstrap SQL as postgres user.
Design: Execute `create_database.sql` then `configure_database.sql` with postgres credentials.
Tests:
- Verify bootstrap SQL scripts execute in expected order.

R030  Statement: Build teller schema objects in declared dependency order.
Design: Execute teller SQL files sequentially as teller user against `prod`.
Tests:
- Verify later table creation depends on earlier files and run succeeds in listed order.

R035  Statement: Resolve SQL file directory relative to script location.
Design: Use `sql/postgres` under script directory.
Tests:
- Run script from a different working directory and verify SQL files still resolve.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `04_deploy_database.sh`.
