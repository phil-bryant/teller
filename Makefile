SHELL := /bin/zsh

# Targets are thin facades over the numbered scripts and tests/t*.sh lanes,
# which remain the single source of truth for each workflow.
TELLER_REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CORE_DIR := $(TELLER_REPO_ROOT)/src/core
CORE_BUILD_DIR ?= $(CORE_DIR)/build
CORE_BUILD_TYPE ?= RelWithDebInfo
NCPU := $(shell sysctl -n hw.ncpu)

.DEFAULT_GOAL := help

.PHONY: help core test sanitize parity pg-test fetch test-all clean

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

# Build the C++ core deterministically through cmake.
core:
	@cmake -S "$(CORE_DIR)" -B "$(CORE_BUILD_DIR)" -DCMAKE_BUILD_TYPE=$(CORE_BUILD_TYPE) >/dev/null
	@cmake --build "$(CORE_BUILD_DIR)" -j $(NCPU)

# Fast C++ core unit lane.
test:
	@"$(TELLER_REPO_ROOT)/tests/t15_run_cpp_core_unit_tests.sh"

# C++ core suite under ASan+UBSan.
sanitize:
	@"$(TELLER_REPO_ROOT)/tests/t16_run_cpp_core_sanitizer_tests.sh"

# Python/C++ persist parity oracle (keeps the Python library honest while it
# remains the matchy dependency).
parity:
	@"$(TELLER_REPO_ROOT)/tests/t17_run_python_cpp_oracle_parity_test.sh"

# libpq backend integration against a live local PostgreSQL.
pg-test:
	@"$(TELLER_REPO_ROOT)/tests/t18_run_cpp_postgres_integration_tests.sh"

# Build then run the C++ Teller API ingest CLI (port of 07_fetch_teller_api_data.py).
fetch: core
	@"$(CORE_BUILD_DIR)/teller_fetch" $(ARGS)

# Run every discovered tests/t*.sh lane through the parallel runner.
test-all:
	@"$(TELLER_REPO_ROOT)/06_run_all_tests_parallel.sh"

# Remove generated artifacts via the canonical clean script plus core build trees.
clean:
	@"$(TELLER_REPO_ROOT)/96_clean_generated_files.sh"
	@rm -rf "$(CORE_DIR)/build" "$(CORE_DIR)/build-asan" "$(CORE_DIR)/build-parity" \
		"$(CORE_DIR)/build-pg"
	@echo "Cleaned core build trees."
