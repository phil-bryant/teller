# Repair nys_snw_category Constraints Requirements

## Scope

Applies to `src/scripts/repair_nys_snw_category.sql`.

R001  Statement: Normalize mutable hierarchy text fields before constraint enforcement.
Design: Trim whitespace, strip control characters, and convert empty strings to `NULL` for hierarchy/categorization/applicability columns.
Tests:
- R001-T01: Verify the SQL script contains normalization updates for all targeted mutable hierarchy fields.

R005  Statement: Block constraint installation when empty hierarchy rows remain.
Design: Use a guard `DO` block that counts empty rows and raises an exception before applying constraints when any invalid rows persist.
Tests:
- R005-T01: Verify the guard block checks emptiness and raises a descriptive exception for non-compliant data.

R010  Statement: Recreate and validate non-empty and no-control-character checks.
Design: Drop prior guard constraints if present, add both checks as `NOT VALID`, then validate each constraint explicitly.
Tests:
- R010-T01: Verify DDL includes drop/add/validate sequence for both named constraints.
