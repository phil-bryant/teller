SHELL := /bin/zsh

#R040: Targets stay thin facades over numbered scripts and tests/t*.sh lanes,
#R040: which remain the single source of truth for each workflow.
TELLER_REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CORE_DIR := $(TELLER_REPO_ROOT)/src/core
CORE_BUILD_DIR ?= $(CORE_DIR)/build
CORE_BUILD_TYPE ?= RelWithDebInfo
NCPU := $(shell sysctl -n hw.ncpu)

#R001: Default target is help so entrypoints are discoverable.
.DEFAULT_GOAL := help

.PHONY: help core test sanitize parity pg-test fetch test-all clean

#R001: Expose discoverable consolidated developer entrypoints.
help:
	@echo "Targets:"
	@echo "  make core      - Build the C++ core (tellercore + tools, $(CORE_BUILD_TYPE))"
	@echo "  make test      - Run the C++ core unit lane (t15)"
	@echo "  make sanitize  - Run the C++ core suite under ASan+UBSan (t16)"
	@echo "  make parity    - Run the Python/C++ persist parity oracle (t17)"
	@echo "  make pg-test   - Run the C++ PostgreSQL integration lane (t18, needs local PG)"
	@echo "  make fetch     - Build the core, then run teller_fetch (Teller API ingest)"
	@echo "  make test-all  - Run every discovered tests/t*.sh lane in parallel"
	@echo "  make clean     - Remove local core build trees"

#R005: Build the portable C++ core deterministically through cmake.
core:
	@cmake -S "$(CORE_DIR)" -B "$(CORE_BUILD_DIR)" -DCMAKE_BUILD_TYPE=$(CORE_BUILD_TYPE) >/dev/null
	@cmake --build "$(CORE_BUILD_DIR)" -j $(NCPU)

#R010: Run the C++ unit suite through the canonical t15 lane.
test:
	@"$(TELLER_REPO_ROOT)/tests/t15_run_cpp_core_unit_tests.sh"

#R015: Expose the C++ sanitizer suite through a dedicated target.
sanitize:
	@"$(TELLER_REPO_ROOT)/tests/t16_run_cpp_core_sanitizer_tests.sh"

#R020: Expose the Python/C++ persist parity lane through a dedicated target.
#R020: Keeps the Python library honest while it remains the matchy dependency.
parity:
	@"$(TELLER_REPO_ROOT)/tests/t17_run_python_cpp_oracle_parity_test.sh"

#R025: Expose the C++ PostgreSQL integration lane through a dedicated target.
pg-test:
	@"$(TELLER_REPO_ROOT)/tests/t18_run_cpp_postgres_integration_tests.sh"

# Build then run the C++ Teller API ingest CLI (port of 07_fetch_teller_api_data.py).
fetch: core
	@"$(CORE_BUILD_DIR)/teller_fetch" $(ARGS)

#R030: Run every discovered tests/t*.sh lane through the canonical parallel runner.
test-all:
	@"$(TELLER_REPO_ROOT)/06_run_all_tests_parallel.sh"

#R035: Remove generated artifacts and local core build trees through one target.
clean:
	@"$(TELLER_REPO_ROOT)/96_clean_generated_files.sh"
	@rm -rf "$(CORE_DIR)/build" "$(CORE_DIR)/build-asan" "$(CORE_DIR)/build-parity" \
		"$(CORE_DIR)/build-pg"
	@echo "Cleaned core build trees."
