# mutmut Darwin Driver Requirements

## Scope

Applies to `src/scripts/mutmut_darwin.py`.

R001  Statement: Provide a macOS-safe mutmut flow that avoids in-process fork crashes.
Design: Split operation into `prepare` and `execute` phases, generating mutants/stats first and then running mutant test subsets through subprocess `pytest`.
Tests:
- R001-T01: Verify command routing and execute-path behavior for prepared and unprepared mutant states.

R005  Statement: Preserve deterministic mutant execution environment.
Design: Configure `PYTHONPATH`, virtualenv PATH, bytecode suppression, and cache paths while mapping exit codes to kill/survive outcomes and persisting per-mutant metadata updates.
Tests:
- R005-T01: Verify subprocess pytest invocation arguments/environment and per-mutant metadata updates.

R010  Statement: Stub `setproctitle` before mutmut import side effects on Darwin.
Design: Register `setproctitle` stub module via `mutmut_darwin_stub.py` so mutmut startup remains stable on macOS runtimes affected by the fork crash path.
Tests:
- R010-T01: Verify the stub module installs a callable `setproctitle` symbol and can be imported before mutmut bootstrap.

R370  Statement: Purge __pycache__ folders under mutants root.
Design: Remove stale bytecode caches in mutant artifact trees.
Tests:
- R370-T01: Verify pycache purge helper is available for mutation prep.

R371  Statement: Resolve repository root path for mutation run.
Design: Resolve repo root used by prepare/execute paths.
Tests:
- R371-T01: Verify repo-root helper is available for run context resolution.

R372  Statement: Prepare mutants with bounded child workers.
Design: Run prepare phase with configured max children value.
Tests:
- R372-T01: Verify prepare helper is available for mutation setup.

R373  Statement: Load mutmut stats payload.
Design: Load mutmut-generated stats metadata from disk.
Tests:
- R373-T01: Verify stats loader helper is available for execute planning.

R374  Statement: Resolve tests for one mutant candidate.
Design: Resolve test targets for a specific mutant id.
Tests:
- R374-T01: Verify tests-for-mutant helper is available for targeted execution.

R375  Statement: Run pytest for one mutant candidate.
Design: Execute targeted pytest subprocess for one mutant.
Tests:
- R375-T01: Verify mutant-pytest helper is available for targeted run.

R376  Statement: Decide whether mutant should rerun.
Design: Apply rerun policy based on existing mutant metadata.
Tests:
- R376-T01: Verify rerun-decision helper is available for execute filtering.

R377  Statement: Map process exit code to mutant status.
Design: Map subprocess return codes to mutation status labels.
Tests:
- R377-T01: Verify exit-code status mapper helper is available for result mapping.

R378  Statement: Run and record one mutant result.
Design: Execute one mutant and persist result metadata.
Tests:
- R378-T01: Verify run-and-record helper is available for per-mutant execution.

R379  Statement: Execute mutants for one source path.
Design: Run all candidate mutants associated with one path.
Tests:
- R379-T01: Verify path-level execute helper is available for per-path runs.

R380  Statement: Execute full mutation run orchestration.
Design: Execute mutation workflow across configured candidate paths.
Tests:
- R380-T01: Verify execute orchestrator helper is available for full run.

R381  Statement: Orchestrate mutmut CLI command routing and exits.
Design: Route prepare/execute commands and propagate exit status.
Tests:
- R381-T01: Verify mutmut main entrypoint is available for command routing.
