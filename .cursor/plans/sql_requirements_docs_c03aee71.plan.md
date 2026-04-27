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
- Keep [`./requirements/06_deploy_database-requirements.md`](./requirements/06_deploy_database-requirements.md) as the deployment-orchestration contract for [`./06_deploy_database.sh`](./06_deploy_database.sh), including ordered execution of SQL files and post-DDL steps.
- Keep [`./requirements/teller_object-requirements.md`](./requirements/teller_object-requirements.md) as the source of truth for ORM naming/mapping behavior (table-name derivation and API aliasing), which already explains most table-column correspondence.

## SQL files that should get their own requirements docs
- Add a dedicated requirements doc for [`./sql/postgres/create_triggers.sql`](./sql/postgres/create_triggers.sql) because it contains non-trivial dynamic trigger generation logic not represented by a single `TellerObject` subclass.
- Add a dedicated requirements doc for [`./sql/postgres/create_audit.sql`](./sql/postgres/create_audit.sql) because it defines cross-table auditing behavior, helper functions, and trigger fan-out that are independent of ORM field mirroring.
- Add a dedicated requirements doc for [`./sql/postgres/teller_transaction_info_view.sql`](./sql/postgres/teller_transaction_info_view.sql) because it defines a derived read-model/view contract consumed by downstream reporting/query workflows.

## SQL files that do not need standalone docs (recommended)
- Do not create per-file requirements docs for the core table DDL files under [`./sql/postgres`](./sql/postgres) that mirror `TellerObject` subclasses (for example `teller_account.sql`, `teller_identity_*.sql`, `teller_transaction*.sql`, etc.).
- Treat those as schema artifacts covered by:
  - ORM mapping requirements in [`./requirements/teller_object-requirements.md`](./requirements/teller_object-requirements.md), and
  - deployment/order guarantees in [`./requirements/06_deploy_database-requirements.md`](./requirements/06_deploy_database-requirements.md).
- Keep the known exception handling explicit in docs where applicable (`self` -> `self_link`, `primary` -> `primary_address`, `id` aliasing patterns).

## Optional boundary decision (if you want stricter SQL-spec ownership)
- If you want SQL to be self-describing independent of Python, add one aggregate doc for schema primitives like [`./sql/postgres/create_database.sql`](./sql/postgres/create_database.sql), [`./sql/postgres/configure_database.sql`](./sql/postgres/configure_database.sql), and [`./sql/postgres/teller_enums.sql`](./sql/postgres/teller_enums.sql); otherwise keep them under deploy requirements only to avoid duplication.

## Proposed natural doc set (minimal)
- Existing: [`./requirements/06_deploy_database-requirements.md`](./requirements/06_deploy_database-requirements.md)
- Existing: [`./requirements/teller_object-requirements.md`](./requirements/teller_object-requirements.md)
- New: `requirements/create_triggers-requirements.md`
- New: `requirements/create_audit-requirements.md`
- New: `requirements/teller_transaction_info_view-requirements.md`