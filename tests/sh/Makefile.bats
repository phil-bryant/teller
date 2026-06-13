#!/usr/bin/env bats

load "helpers/common.bash"

setup() {
  #R001: Make-test harness setup builds a sandboxed repo with stubbed scripts.
  setup_shell_test
  SANDBOX="${TEST_TMPDIR}/sandbox"
  export SANDBOX
  mkdir -p "${SANDBOX}/tests" "${SANDBOX}/src/core/build" "${SANDBOX}/src/core/build-asan"
  # make's CURDIR is the physical path; greps must match it (macOS /var symlink).
  SANDBOX_REAL="$(cd "${SANDBOX}" && pwd -P)"
  export SANDBOX_REAL
  cp "$(repo_root)/Makefile" "${SANDBOX}/Makefile"

  for SCRIPT in \
    06_run_all_tests_parallel.sh \
    96_clean_generated_files.sh \
    tests/t15_run_cpp_core_unit_tests.sh \
    tests/t16_run_cpp_core_sanitizer_tests.sh \
    tests/t17_run_python_cpp_oracle_parity_test.sh \
    tests/t18_run_cpp_postgres_integration_tests.sh; do
    create_logging_stub_script "${SANDBOX}/${SCRIPT}"
  done

  create_logging_stub_tool cmake
}

teardown() {
  #R001: Make-test harness teardown removes the sandbox.
  teardown_shell_test
}

create_logging_stub_script() {
  #R040: Stub canonical scripts so tests assert delegation, not behavior.
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
#!/bin/bash
printf '%s %s\n' "\$(basename "\$0")" "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "$path"
}

create_logging_stub_tool() {
  #R005: Stub toolchain binaries (cmake) onto the test PATH.
  local tool="$1"
  cat > "${STUB_BIN}/${tool}" <<EOF
#!/bin/bash
printf '%s %s\n' "${tool}" "\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/${tool}"
}

run_make() {
  #R001: All make invocations run against the sandbox with stubbed PATH.
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" make -C "${SANDBOX}" "$@"
}

@test "R001-T01: help target lists all consolidated developer targets with descriptions" {
  #R001-T01: help target lists all consolidated developer targets with descriptions.
  run_make help
  [ "$status" -eq 0 ]
  for TARGET in core test sanitize parity pg-test test-all clean; do
    [[ "$output" == *"make ${TARGET}"* ]]
  done
}

@test "R001-T02: help is the default goal when make runs with no arguments" {
  #R001-T02: help is the default goal when make runs with no arguments.
  run_make
  [ "$status" -eq 0 ]
  [[ "$output" == *"Targets:"* ]]
}

@test "R005-T01: core target runs cmake configure and parallel build against src/core" {
  #R005-T01: core target runs cmake configure and parallel build against src/core.
  run_make core
  [ "$status" -eq 0 ]
  grep -q "cmake -S ${SANDBOX_REAL}/src/core -B ${SANDBOX_REAL}/src/core/build" "$CALLS_LOG"
  grep -q "cmake --build ${SANDBOX_REAL}/src/core/build -j" "$CALLS_LOG"
}

@test "R010-T01: test delegates to the t15 lane script" {
  #R010-T01: test delegates to the t15 lane script.
  run_make test
  [ "$status" -eq 0 ]
  grep -q "^t15_run_cpp_core_unit_tests.sh" "$CALLS_LOG"
}

@test "R015-T01: sanitize delegates to the t16 lane script" {
  #R015-T01: sanitize delegates to the t16 lane script.
  run_make sanitize
  [ "$status" -eq 0 ]
  grep -q "^t16_run_cpp_core_sanitizer_tests.sh" "$CALLS_LOG"
}

@test "R020-T01: parity delegates to the t17 lane script" {
  #R020-T01: parity delegates to the t17 lane script.
  run_make parity
  [ "$status" -eq 0 ]
  grep -q "^t17_run_python_cpp_oracle_parity_test.sh" "$CALLS_LOG"
}

@test "R025-T01: pg-test delegates to the t18 lane script" {
  #R025-T01: pg-test delegates to the t18 lane script.
  run_make pg-test
  [ "$status" -eq 0 ]
  grep -q "^t18_run_cpp_postgres_integration_tests.sh" "$CALLS_LOG"
}

@test "R030-T01: test-all delegates to the parallel aggregate runner" {
  #R030-T01: test-all delegates to the parallel aggregate runner.
  run_make test-all
  [ "$status" -eq 0 ]
  grep -q "^06_run_all_tests_parallel.sh" "$CALLS_LOG"
}

@test "R035-T01: clean runs the canonical clean script and removes both core build directories" {
  #R035-T01: clean runs the canonical clean script and removes both core build directories.
  touch "${SANDBOX}/src/core/build/marker" "${SANDBOX}/src/core/build-asan/marker"
  run_make clean
  [ "$status" -eq 0 ]
  grep -q "^96_clean_generated_files.sh" "$CALLS_LOG"
  [ ! -d "${SANDBOX}/src/core/build" ]
  [ ! -d "${SANDBOX}/src/core/build-asan" ]
}

@test "R040-T01: every non-build target's recipe invokes a canonical script rather than inlining logic" {
  #R040-T01: every non-build target's recipe invokes a canonical script rather than inlining logic.
  for TARGET_SCRIPT in \
    "test:t15_run_cpp_core_unit_tests.sh" \
    "sanitize:t16_run_cpp_core_sanitizer_tests.sh" \
    "parity:t17_run_python_cpp_oracle_parity_test.sh" \
    "pg-test:t18_run_cpp_postgres_integration_tests.sh" \
    "test-all:06_run_all_tests_parallel.sh" \
    "clean:96_clean_generated_files.sh"; do
    TARGET="${TARGET_SCRIPT%%:*}"
    SCRIPT="${TARGET_SCRIPT#*:}"
    : > "$CALLS_LOG"
    run_make "$TARGET"
    [ "$status" -eq 0 ]
    grep -q "^${SCRIPT}" "$CALLS_LOG"
  done
}
