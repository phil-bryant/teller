# Install Venv Test Cache Env Requirements

## Scope

Applies to `src/scripts/install_venv_test_cache_env.sh`.

R001  Statement: Append teller cache-env exports to a venv activate script idempotently.
Design: Define `install_venv_test_cache_env(venv_dir)` to append a teller-marked block to `bin/activate` once; skip when the marker is already present.
Tests:
- R001-T01: Verify activate script contains exactly one teller cache marker after two install calls.

R005  Statement: Fail when the venv activate script is missing.
Design: Return non-zero with a clear error when `${venv_dir}/bin/activate` does not exist.
Tests:
- R005-T01: Verify missing activate script produces an explicit failure message.
