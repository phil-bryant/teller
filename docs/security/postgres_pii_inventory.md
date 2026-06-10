# Postgres PII Inventory (Pre-Prod)

This inventory classifies current `teller` schema fields for pre-production hardening.

## Sensitivity Classes

- `Public`: safe to expose broadly.
- `Internal`: operational metadata with low sensitivity.
- `Confidential`: business data that should be restricted by least privilege.
- `Restricted-PII`: directly identifying or financial account data requiring masking, hashing, and strict access controls.

## Restricted-PII Fields

| Table | Column(s) | Why |
| --- | --- | --- |
| `teller.account_details` | `account_number` | Full financial account identifier. |
| `teller.identity_email` | `data` | Direct personal identifier. |
| `teller.identity_phone_number` | `data` | Direct personal identifier. |
| `teller.identity_address_data` | `street`, `city`, `region`, `country`, `postal_code` | Home/work address identity data. |

## Confidential Fields

| Table | Column(s) | Why |
| --- | --- | --- |
| `teller.transaction` | `description`, `amount`, `running_balance`, `date` | Financial behavior and balances. |
| `matchy.transaction_email_candidate` | `cached_subject`, `cached_sender`, `cached_snippet` | May contain personal message content. |
| `matchy.transaction_email_match` | `email_message_id` | Links transactions to personal communications. |
| `teller.account` | `enrollment_id`, `name` | Account linkage metadata. |

## Internal Fields

- Internal IDs, foreign keys, timestamps, and categorical enums that do not directly identify a person by themselves.

## Control Mapping

- Restricted-PII fields: masked secure views + deterministic hash columns + RLS + strict role-based grants.
- Confidential fields: RLS + least-privilege role access + audit coverage.
- Internal fields: baseline role grants and audit logging.
