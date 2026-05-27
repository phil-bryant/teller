---
name: dot-config-relocation-candidates
overview: Identify which hidden root files/directories can be moved under a new config directory without breaking tooling or violating common conventions, and define a safe migration order.
todos:
  - id: classify-dot-paths
    content: Classify hidden root paths into immutable/tool-convention vs movable config vs runtime artifacts
    status: completed
  - id: migrate-security-configs
    content: Move only security policy files to config/security and parameterize script references
    status: completed
  - id: update-tests-docs
    content: Align Bats tests and README path expectations with new config/security defaults
    status: completed
  - id: preserve-runtime-layout
    content: Keep report/cache/venv directories out of config and maintain current runtime behavior
    status: completed
isProject: false
---

# Dotfile Relocation Assessment

## Recommended Keepers At Repo Root (not candidates)
- Keep [`/Users/phil/local/src/teller/.gitignore`](/Users/phil/local/src/teller/.gitignore) at root (Git behavior is convention/root-scoped).
- Keep [`/Users/phil/local/src/teller/.git`](/Users/phil/local/src/teller/.git) and [`/Users/phil/local/src/teller/.cursor`](/Users/phil/local/src/teller/.cursor) where they are (tooling expects these exact locations).
- Keep [`/Users/phil/local/src/teller/.cursorignore`](/Users/phil/local/src/teller/.cursorignore) at root (Cursor ignore file is root-convention based).

## Best Candidates To Move Into `config/` (low conceptual weirdness)
- [`/Users/phil/local/src/teller/.bandit`](/Users/phil/local/src/teller/.bandit)
- [`/Users/phil/local/src/teller/.semgrep.yml`](/Users/phil/local/src/teller/.semgrep.yml)
- [`/Users/phil/local/src/teller/.gitleaksignore`](/Users/phil/local/src/teller/.gitleaksignore)

These are true policy/config artifacts (not runtime caches), so moving them into `config/security/` is structurally clean.

## Why These Need Coordinated Ref Updates
Current scripts hardcode root-relative names:
- [`/Users/phil/local/src/teller/06_run_static_security_tests.sh`](/Users/phil/local/src/teller/06_run_static_security_tests.sh) references `.gitleaksignore`, `.semgrep.yml`, and `./.bandit`.
- [`/Users/phil/local/src/teller/22_run_dynamic_security_tests.sh`](/Users/phil/local/src/teller/22_run_dynamic_security_tests.sh) references the same files.
- Tests and docs also assume these names:
  - [`/Users/phil/local/src/teller/tests/sh/06_run_static_security_tests.bats`](/Users/phil/local/src/teller/tests/sh/06_run_static_security_tests.bats)
  - [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md)

## Not Good `config/` Moves (runtime/output, not config)
- Runtime/report/cache dirs should stay as runtime paths or move to `artifacts/`/`var/`, not `config/`:
  - [`/Users/phil/local/src/teller/.security-reports`](/Users/phil/local/src/teller/.security-reports)
  - [`/Users/phil/local/src/teller/.parallel-checks-reports`](/Users/phil/local/src/teller/.parallel-checks-reports)
  - [`/Users/phil/local/src/teller/.security-venv`](/Users/phil/local/src/teller/.security-venv)
  - [`/Users/phil/local/src/teller/.ruff_cache`](/Users/phil/local/src/teller/.ruff_cache)
  - [`/Users/phil/local/src/teller/.pytest_cache`](/Users/phil/local/src/teller/.pytest_cache)
  - [`/Users/phil/local/src/teller/.hypothesis`](/Users/phil/local/src/teller/.hypothesis)

## Optional Cleanup-Only Items (not worth migrating into `config/`)
- [`/Users/phil/local/src/teller/.DS_Store`](/Users/phil/local/src/teller/.DS_Store) (local OS artifact)
- [`/Users/phil/local/src/teller/.tmp_xcode_pref_backup`](/Users/phil/local/src/teller/.tmp_xcode_pref_backup) (temporary backup)
- [`/Users/phil/local/src/teller/.zap`](/Users/phil/local/src/teller/.zap) (tool state directory; avoid treating as source config)

## Safe Migration Sequence
1. Create `config/security/` as new home for security policy files.
2. Move only `.bandit`, `.semgrep.yml`, `.gitleaksignore` first.
3. Add explicit script variables (for example `BANDIT_CONFIG_PATH`, `SEMGREP_CONFIG_PATH`, `GITLEAKS_IGNORE_PATH`) with defaults pointing to new `config/security/*` paths.
4. Update test fixtures and assertions in shell bats tests to match new defaults.
5. Update docs examples and path references.
6. Keep backward compatibility briefly (accept old root paths if present) to avoid breakage during transition.
7. After green tests, remove backward-compat fallback.

## Guardrail
Do not move report/cache/venv directories into `config/`; that makes repository semantics more confusing and increases accidental scanner/input coupling risks already managed in the current scripts.