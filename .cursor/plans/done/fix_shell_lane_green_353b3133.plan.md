---
name: Fix shell lane green
overview: Repair shell unit test fixture resolution so `13_validate_quality_target` tests use the active runner implementation instead of a removed teller-root script, then validate locally and in the full parallel suite.
todos:
  - id: update-fixture-source-resolution
    content: Extend `copy_script_to_fixture` fallback resolution in `tests/sh/helpers/common.bash` to include sibling runner scripts and explicit missing-source error.
    status: completed
  - id: verify-shell-unit-lane
    content: Run `./tests/t07_run_shell_unit_tests.sh` and confirm `13_validate_quality_target` bats cases pass.
    status: completed
  - id: verify-full-parallel-suite
    content: Run `./06_run_all_tests_parallel.sh` and confirm full green with no skips/suppressions.
    status: completed
isProject: false
---

# Fix `t07_run_shell_unit_tests` path regression

## Root Cause
`tests/sh/13_validate_quality_target.bats` calls `copy_script_to_fixture "13_validate_quality_target.sh"`, but teller no longer has that file at repo root. The active implementation now lives in sibling runner at `../runner/13_validate_quality_target.sh`. Current fixture resolution in [tests/sh/helpers/common.bash](tests/sh/helpers/common.bash) only checks teller root and `tests/`, so copy fails and the lane aborts.

## Changes to Make
- Update script-source resolution in [tests/sh/helpers/common.bash](tests/sh/helpers/common.bash) (`copy_script_to_fixture`) to search in this order:
  1) teller repo root (`${repo_root}/${script_name}`)
  2) teller tests (`${repo_root}/tests/${script_name}`)
  3) sibling runner (`${repo_root}/../runner/${script_name}`)
- Keep the existing fixture destination and chmod behavior unchanged so all existing `.bats` callers keep working.
- Add a clear failure message if none of the source candidates exist (instead of opaque `cp` failure), to make future renumbering/moves easier to diagnose.

## Validation
- Run focused lane: `./tests/t07_run_shell_unit_tests.sh` and verify `tests/sh/13_validate_quality_target.bats` passes all 3 scenarios.
- Run full gate: `./06_run_all_tests_parallel.sh` and verify `15/15` pass.
- Confirm no lane was skipped and no filter flags were introduced.
