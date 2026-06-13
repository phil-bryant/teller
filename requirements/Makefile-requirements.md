# Makefile Requirements

## Scope

Applies to repository task automation in `Makefile` for consolidated local build and
test workflows around the C++ core. Targets are thin facades over the numbered
scripts and the numbered test lanes, which remain the single source of truth
(same convention as classy's Makefile).

R001  Statement: Expose discoverable consolidated developer entrypoints through a help target.
Design: `make help` (the default goal) lists supported targets and a one-line purpose for each (`core`, `test`, `sanitize`, `parity`, `pg-test`, `test-all`, `clean`).
Tests:
- R001-T01: help target lists all consolidated developer targets with descriptions.
- R001-T02: help is the default goal when make runs with no arguments.

R005  Statement: Build the portable C++ core deterministically through cmake.
Design: `make core` configures `src/core` into `CORE_BUILD_DIR` (default `src/core/build`) with `CMAKE_BUILD_TYPE=$(CORE_BUILD_TYPE)` (default `RelWithDebInfo`) and builds with `-j $(NCPU)`.
Tests:
- R005-T01: core target runs cmake configure and parallel build against src/core.

R010  Statement: Run the C++ unit suite through the canonical t15 lane.
Design: `make test` delegates to the t15 lane script (C++ core unit tests).
Tests:
- R010-T01: test delegates to the t15 lane script.

R015  Statement: Expose the C++ sanitizer suite through a dedicated target.
Design: `make sanitize` delegates to the t16 lane script (ASan+UBSan rebuild and rerun in `src/core/build-asan`).
Tests:
- R015-T01: sanitize delegates to the t16 lane script.

R020  Statement: Expose the Python/C++ oracle parity lane through a dedicated target.
Design: `make parity` delegates to the t17 lane script (live Python reference vs C++ core on identical fixtures; postgres backend included when admin credentials resolve).
Tests:
- R020-T01: parity delegates to the t17 lane script.

R025  Statement: Expose the C++ PostgreSQL integration lane through a dedicated target.
Design: `make pg-test` delegates to the t18 lane script (scratch-database provisioning plus postgres-tagged Catch2 cases; clean skip without admin credentials).
Tests:
- R025-T01: pg-test delegates to the t18 lane script.

R030  Statement: Run every discovered numbered lane through the canonical parallel runner.
Design: `make test-all` delegates to `06_run_all_tests_parallel.sh`.
Tests:
- R030-T01: test-all delegates to the parallel aggregate runner.

R035  Statement: Remove generated artifacts and local core build trees through one target.
Design: `make clean` runs `96_clean_generated_files.sh`, then removes `src/core/build` and `src/core/build-asan`.
Tests:
- R035-T01: clean runs the canonical clean script and removes both core build directories.

R040  Statement: Keep Makefile targets thin facades over canonical scripts and lanes.
Design: No target inlines workflow logic; each delegates to a numbered script or `tests/t*.sh` lane so the scripts stay the single source of truth.
Tests:
- R040-T01: every non-build target's recipe invokes a canonical script rather than inlining logic.

## Changelog

- 2026-06-12: Initial version alongside the Python -> C++ core migration (M0-M5).
