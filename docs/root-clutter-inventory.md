# Root Clutter Inventory

This inventory classifies root-level path assumptions discovered in scripts, tests, and docs during the cleanup pass.

## Movable via defaults/env

- Security and freshness report outputs
  - Current knobs: `SECURITY_REPORT_DIR`, `DEPENDENCY_REPORT_DIR`, `TELLER_SMOKE_REPORT_DIR`
  - New default target: `artifacts/security`
  - Legacy compatibility: existing env vars still override defaults.
- Parallel aggregate outputs
  - Current knob: `PARALLEL_CHECKS_REPORT_DIR`
  - New default target: `artifacts/parallel`
- Mutation outputs
  - Current knob: `MUTATION_REPORT_DIR`
  - New default target: `artifacts/mutation`
- Fuzz outputs
  - Current knob: `FUZZ_REPORT_DIR`
  - New default target: `artifacts/fuzz`

## Config relocation

- DB profile config search uses organized config paths:
  1. `TELLER_DB_PROFILE_FILE` (explicit override)
  2. `~/.teller/db_profiles.json`
  3. `config/db-profiles.local.json`
  4. `config/db-profiles.json`

## Keep at root

- Numbered script entrypoints (`00`-`24`, `97`-`99`) remain root-level.
- Core project metadata remains root-level (`pyproject.toml`, `requirements*.txt`, `README.md`).
- DB profile files live under `config/` (`config/db-profiles*.json`).

## Generated/cache paths under artifacts

- `__pycache__`, `artifacts/cache/pytest`, `artifacts/cache/ruff`, `artifacts/cache/hypothesis`, `artifacts/cache/egg-info/teller.egg-info`
- Runtime cache/report/venv outputs are expected under `artifacts/`:
  - `artifacts/security`
  - `artifacts/parallel`
  - `artifacts/venv/security`
