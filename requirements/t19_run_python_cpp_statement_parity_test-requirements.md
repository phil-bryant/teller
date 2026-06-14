# t19 run python cpp statement parity test Requirements

## Scope

Applies to `tests/t19_run_python_cpp_statement_parity_test.sh`, the self-contained
teller-owned statement-parsing parity lane that drives every statement scenario
through both the Python reference and the C++ core, diffing parsed transactions,
deterministic ids, period, and summary totals. There is no runner delegation
(thick lane).

R001  Statement: Lane requires the teller-venv interpreter before running parity.
Design: Verify `teller-venv/bin/python3` is executable and exit 2 with remediation guidance otherwise.
Tests:
- R001-T01: Verify the lane requires the teller-venv python and fails with guidance when absent.

R005  Statement: Lane builds the C++ oracle runner in a lane-private build tree.
Design: Configure RelWithDebInfo into `build-parity` and build the `teller_oracle_runner` target.
Tests:
- R005-T01: Verify the lane builds the `teller_oracle_runner` target.

R010  Statement: Lane diffs Python vs C++ statement parsing results.
Design: Run `oracle/compare_statement_oracle.py --runner <teller_oracle_runner>` via the venv python.
Tests:
- R010-T01: Verify the lane runs `compare_statement_oracle.py` against the built runner.
