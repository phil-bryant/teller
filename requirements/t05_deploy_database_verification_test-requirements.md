# deploy database verification test Requirements

## Scope

Applies to `tests/t05_deploy_database_verification_test.sh`.

R005  Statement: Use connection settings exclusively from the resolved profile (1psa or ~/.env via the helper).
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R005` tagged block.
Tests:
- R005-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R005` implementation tag.

R010  Statement: Resolve DB password from environment or 1psa fallback.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R010` tagged block.
Tests:
- R010-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R010` implementation tag.

R015  Statement: Refuse verification when DB password resolves empty.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R015` tagged block.
Tests:
- R015-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R015` implementation tag.

R020  Statement: Verify required deployed roles exist.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R020` tagged block.
Tests:
- R020-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R020` implementation tag.

R025  Statement: Verify classification FK uses ON DELETE CASCADE.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R025` tagged block.
Tests:
- R025-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R025` implementation tag.

R030  Statement: Verify updated_at trigger function and table trigger exist.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R030` tagged block.
Tests:
- R030-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R030` implementation tag.

R035  Statement: Print explicit pass/fail verification result.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R035` tagged block.
Tests:
- R035-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R035` implementation tag.

R040  Statement: Verify every teller table with updated_at is covered by teller.update_updated_at.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R040` tagged block.
Tests:
- R040-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R040` implementation tag.

R045  Statement: Surface all missing table names as explicit verification failures.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R045` tagged block.
Tests:
- R045-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R045` implementation tag.

R050  Statement: Resolve target/profile so verification can adapt to local vs managed Postgres.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R050` tagged block.
Tests:
- R050-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R050` implementation tag.

R055  Statement: Resolve DB password from environment or profile-driven 1psa fallback.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R055` tagged block.
Tests:
- R055-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R055` implementation tag.

R060  Statement: When the resolved profile requires TLS, confirm the live connection is encrypted.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R060` tagged block.
Tests:
- R060-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R060` implementation tag.

R065  Statement: Refuse verification when DB profile setup is missing.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R065` tagged block.
Tests:
- R065-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R065` implementation tag.

R066  Statement: Run SQLite-specific verification checks when the active profile target is SQLite.
Design: Implemented inline in `tests/t05_deploy_database_verification_test.sh` at the `#R066` tagged block.
Tests:
- R066-T01: Verify `tests/t05_deploy_database_verification_test.sh` carries the `#R066` implementation tag.
