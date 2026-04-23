---
name: sql requirements docs
overview: Recommend a minimal, natural set of requirements documents for SQL sources based on current traceability rules, ORM/table alignment, and existing requirement coverage.
todos:
  - id: classify-sql-files
    content: Classify SQL files into ORM-mirrored tables vs behavior/derived artifacts.
    status: completed
  - id: pick-minimal-doc-set
    content: Select only behavior-rich SQL files that warrant standalone requirements documents.
    status: completed
  - id: define-ownership-boundaries
    content: Define which contracts stay in deploy/ORM requirements to avoid duplication and drift.
    status: completed
isProject: false
---

# SQL Requirements Documentation Recommendation

## What already exists and should remain authoritative
- Keep [`/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md`](/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md) as the deployment-orchestration contract for [`/Users/phil/local/src/teller/05_deploy_database.sh`](/Users/phil/local/src/teller/05_deploy_database.sh), including ordered execution of SQL files and post-DDL steps.
- Keep [`/Users/phil/local/src/teller/requirements/teller_object-requirements.md`](/Users/phil/local/src/teller/requirements/teller_object-requirements.md) as the source of truth for ORM naming/mapping behavior (table-name derivation and API aliasing), which already explains most table-column correspondence.

## SQL files that should get their own requirements docs
- Add a dedicated requirements doc for [`/Users/phil/local/src/teller/sql/postgres/create_triggers.sql`](/Users/phil/local/src/teller/sql/postgres/create_triggers.sql) because it contains non-trivial dynamic trigger generation logic not represented by a single `TellerObject` subclass.
- Add a dedicated requirements doc for [`/Users/phil/local/src/teller/sql/postgres/create_audit.sql`](/Users/phil/local/src/teller/sql/postgres/create_audit.sql) because it defines cross-table auditing behavior, helper functions, and trigger fan-out that are independent of ORM field mirroring.
- Add a dedicated requirements doc for [`/Users/phil/local/src/teller/sql/postgres/teller_transaction_info_view.sql`](/Users/phil/local/src/teller/sql/postgres/teller_transaction_info_view.sql) because it defines a derived read-model/view contract consumed by downstream reporting/query workflows.

## SQL files that do not need standalone docs (recommended)
- Do not create per-file requirements docs for the core table DDL files under [`/Users/phil/local/src/teller/sql/postgres`](/Users/phil/local/src/teller/sql/postgres) that mirror `TellerObject` subclasses (for example `teller_account.sql`, `teller_identity_*.sql`, `teller_transaction*.sql`, etc.).
- Treat those as schema artifacts covered by:
  - ORM mapping requirements in [`/Users/phil/local/src/teller/requirements/teller_object-requirements.md`](/Users/phil/local/src/teller/requirements/teller_object-requirements.md), and
  - deployment/order guarantees in [`/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md`](/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md).
- Keep the known exception handling explicit in docs where applicable (`self` -> `self_link`, `primary` -> `primary_address`, `id` aliasing patterns).

## Optional boundary decision (if you want stricter SQL-spec ownership)
- If you want SQL to be self-describing independent of Python, add one aggregate doc for schema primitives like [`/Users/phil/local/src/teller/sql/postgres/create_database.sql`](/Users/phil/local/src/teller/sql/postgres/create_database.sql), [`/Users/phil/local/src/teller/sql/postgres/configure_database.sql`](/Users/phil/local/src/teller/sql/postgres/configure_database.sql), and [`/Users/phil/local/src/teller/sql/postgres/teller_enums.sql`](/Users/phil/local/src/teller/sql/postgres/teller_enums.sql); otherwise keep them under deploy requirements only to avoid duplication.

## Proposed natural doc set (minimal)
- Existing: [`/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md`](/Users/phil/local/src/teller/requirements/05_deploy_database-requirements.md)
- Existing: [`/Users/phil/local/src/teller/requirements/teller_object-requirements.md`](/Users/phil/local/src/teller/requirements/teller_object-requirements.md)
- New: `requirements/create_triggers-requirements.md`
- New: `requirements/create_audit-requirements.md`
- New: `requirements/teller_transaction_info_view-requirements.md`