# Check Dependency Freshness Requirements

## Scope

Applies to `src/scripts/check_dependency_freshness.py`.

R001  Statement: Parse requirements pins and classify outdated package updates by severity.
Design: Parse `requirements.txt` entries, normalize package names, compare installed and latest versions, and classify each update as `major`, `minor`, `patch`, or `unknown`.
Tests:
- R001-T01: Verify requirements parsing and update classification behavior for pinned and non-pinned dependencies.

R005  Statement: Emit machine-readable and human-readable freshness reports.
Design: Write JSON and text outputs with summary counters plus per-package rows that include direct-requirements membership and pin metadata.
Tests:
- R005-T01: Run the script with mocked outdated package rows and verify both report formats contain expected summary/package fields.

R010  Statement: Enforce optional freshness gates for major updates and direct requirements drift.
Design: Return non-zero when `--fail-on-major` detects major updates or `--fail-on-direct-outdated` detects outdated packages referenced by `requirements.txt`.
Tests:
- R010-T01: Verify each gate independently returns a failing exit status only when its configured condition is present.
