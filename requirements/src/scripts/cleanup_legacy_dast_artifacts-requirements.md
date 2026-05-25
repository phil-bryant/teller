# Cleanup Legacy DAST Artifacts Requirements

## Scope

Applies to `src/scripts/cleanup_legacy_dast_artifacts.sql`.

R001  Statement: Remove legacy DAST orphan rows using conservative fingerprint filters.
Design: Target only non-seed `nys_snw_category` rows with expected DAST markers and `transaction_email_match` rows with schemathesis/dast seeder email fingerprints.
Tests:
- R001-T01: Verify script predicates constrain deletions to expected DAST fingerprint columns/values.

R005  Statement: Delete in foreign-key-safe order and preserve transactional atomicity.
Design: Wrap execution in an explicit transaction and delete dependent classification rows before categories and match rows.
Tests:
- R005-T01: Verify script contains explicit `BEGIN/COMMIT` and dependency-ordered delete statements.

R010  Statement: Surface operator visibility before destructive operations.
Design: Emit pre-delete row-count queries that summarize candidate removals for categories, mappings, and match rows.
Tests:
- R010-T01: Verify script contains pre-delete counting queries for each cleanup domain.
