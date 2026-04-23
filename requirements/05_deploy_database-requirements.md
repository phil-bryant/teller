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

R040  Statement: Attach updated_at triggers after all table DDL creation.
Design: Execute `create_triggers.sql` only after all `teller_*.sql` table files that define `updated_at` are applied.
Tests:
- Verify deploy order runs `create_triggers.sql` after `teller_transaction_nys_snw_category.sql`.

R045  Statement: Ensure transaction classifications cascade-delete with parent transaction removal.
Design: Enforce `ON DELETE CASCADE` on `teller.transaction_nys_snw_category(transaction_id)` during deploy, including existing databases.
Tests:
- Delete a row from `teller.transaction` with a linked `transaction_nys_snw_category` row and verify child row is removed automatically.
- Re-run deploy and verify FK remains present with cascade behavior.

## Changelog

- 2026-04-21: Added R040 trigger-order requirement to ensure full updated_at coverage.
- 2026-04-22: Added R045 to enforce cascading delete behavior for transaction classifications.
- 2026-04-19: Initial reverse-engineered requirements for `04_deploy_database.sh`.
