---
name: mutation-test-quality-roadmap
overview: Assess current mutation testing maturity and define a phased path to reach top-tier (>=95th percentile) effectiveness with measurable gates.
todos:
  - id: tighten-mutation-lane
    content: Harden mutation lane behavior in CI and increase minimum mutator coverage gate.
    status: completed
  - id: strengthen-current-tests
    content: Improve branch/edge-case assertions in existing mutation-targeted Python tests.
    status: completed
  - id: expand-mutation-scope
    content: Grow pyproject mutmut scope in prioritized waves with matching test additions.
    status: completed
  - id: ratchet-to-final-gates
    content: Raise thresholds to 95 score and 90 mutator coverage after scope expansion.
    status: completed
  - id: add-trending-and-review
    content: Persist and review mutation metrics trend to prevent regressions.
    status: completed
isProject: false
---

# Mutation Testing Quality Assessment And 95th-Percentile Roadmap

## Current Rating

Based on current configuration and test architecture, mutation testing quality is **~60th percentile (Developing / constrained)**.

Why:

- Strong foundations: dedicated lane, machine-readable reports, explicit gates in `[11_run_mutation_tests.sh](/Users/phil/local/src/teller/11_run_mutation_tests.sh)`, and mutmut config in `[pyproject.toml](/Users/phil/local/src/teller/pyproject.toml)`.
- Main constraint: mutation scope is intentionally narrow (`only_mutate` targets only 2 modules) while most Python modules are outside mutation evaluation.
- Additional constraint: mutation run disables Hypothesis via `-p no:hypothesis`, and mutmut can soft-skip on host incompatibility.

## What "95th Percentile Good" Should Mean (Target State)

Use these concrete targets:

- **Mutation score:** >= 95% on prioritized critical modules.
- **Mutator coverage:** >= 90% (not just score on a small subset).
- **Scope depth:** >= 8-12 high-impact Python modules in mutation scope, not 2.
- **Run reliability:** mutation lane hard-fails on incompatibility/skip in CI mode.
- **Trend visibility:** persistent historical mutation summaries by module.

## Phased Roadmap

### Phase 1: Stabilize and tighten the current lane (1-2 days)

- Keep existing targets but raise reliability and signal quality in `[11_run_mutation_tests.sh](/Users/phil/local/src/teller/11_run_mutation_tests.sh)`.
- Add strict CI mode: treat `skipped=true` as failure when `CI=true`.
- Enable mutation preflight by default in CI (`MUTATION_SKIP_PREFLIGHT=false` in CI path).
- Raise default `MUTATOR_COVERAGE_THRESHOLD` from 70 to 80 as first ratchet.
- Ensure summary includes per-run metadata (timestamp, git sha, duration).

### Phase 2: Kill more mutants in current scope (2-4 days)

- Strengthen behavior-focused tests for current mutation targets:
  - `[tests/py/test_teller_classification_api.py](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py)`
  - `[tests/py/test_teller_db_profile.py](/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py)`
  - `[tests/py/test_teller_properties.py](/Users/phil/local/src/teller/tests/py/test_teller_properties.py)`
- Add assertions for edge branches likely to survive today: error handling, invariants, comparison and boundary logic.
- Introduce a small HTTP-level FastAPI test slice (e.g., request/response semantics) to complement direct handler tests.
- Re-enable property-test contribution during mutation for deterministic subsets.

### Phase 3: Expand mutation scope with risk-based prioritization (1-2 weeks)

- Expand `only_mutate` in `[pyproject.toml](/Users/phil/local/src/teller/pyproject.toml)` in waves:
  1. classification + persistence-adjacent modules
  2. DB interaction helpers
  3. transaction/account identity modules
- For each newly-mutated module, add/expand focused tests first, then enable mutation.
- Remove modules from `do_not_mutate` only when baseline tests exist.
- Gate each wave by achieving >=92% score and >=85% mutator coverage before adding the next wave.

### Phase 4: Reach and hold 95th percentile (ongoing)

- Ratchet gates to final targets:
  - `MUTATION_SCORE_THRESHOLD=95`
  - `MUTATOR_COVERAGE_THRESHOLD=90`
- Add a budget for surviving mutants (must decrease week-over-week).
- Add a lightweight monthly mutation review (top surviving mutant classes, owner, due date).

## Suggested Execution Flow

```mermaid
flowchart LR
baseline[BaselineLane] --> strengthen[StrengthenCurrentTests]
strengthen --> expand[ExpandMutationScope]
expand --> ratchet[RatchetThresholds]
ratchet --> sustain[SustainAndTrend]
```



## High-Impact File Touchpoints

- Runner and policy:
  - `[11_run_mutation_tests.sh](/Users/phil/local/src/teller/11_run_mutation_tests.sh)`
  - `[requirements/11_run_mutation_tests-requirements.md](/Users/phil/local/src/teller/requirements/11_run_mutation_tests-requirements.md)`
- Mutation config:
  - `[pyproject.toml](/Users/phil/local/src/teller/pyproject.toml)`
- Current mutation-targeted tests:
  - `[tests/py/test_teller_classification_api.py](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py)`
  - `[tests/py/test_teller_db_profile.py](/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py)`
  - `[tests/py/test_teller_properties.py](/Users/phil/local/src/teller/tests/py/test_teller_properties.py)`

## Success Criteria (Definition of Done)

- Mutation lane runs reliably on dev + CI without soft-skip escapes.
- At least 8 modules are actively mutated with meaningful tests.
- Rolling 2-week median reaches >=95 mutation score and >=90 mutator coverage.
- Surviving mutants are triaged and tracked to closure.

