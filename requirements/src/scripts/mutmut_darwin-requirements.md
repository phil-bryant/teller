# mutmut Darwin Driver Requirements

## Scope

Applies to `src/scripts/mutmut_darwin.py` and `src/scripts/mutmut_darwin_stub.py`.

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
