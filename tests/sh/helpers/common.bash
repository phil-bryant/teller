#!/usr/bin/env bash

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

setup_shell_test() {
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export HOME="${TEST_TMPDIR}/home"
  mkdir -p "$HOME"

  export STUB_BIN="${TEST_TMPDIR}/test-bin"
  mkdir -p "$STUB_BIN"
  export CALLS_LOG="${TEST_TMPDIR}/calls.log"
  : > "$CALLS_LOG"

  export PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown_shell_test() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR}" ]]; then
    /bin/rm -rf "$TEST_TMPDIR"
  fi
}

create_repo_fixture() {
  export FIXTURE_ROOT="${TEST_TMPDIR}/fixture"
  mkdir -p "$FIXTURE_ROOT"
}

copy_test_cache_env_scripts_to_fixture() {
  mkdir -p "${FIXTURE_ROOT}/src/scripts"
  cp "$(repo_root)/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh"
  cp "$(repo_root)/src/scripts/normalize_pytest_addopts.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
  chmod +x "${FIXTURE_ROOT}/src/scripts/export_test_cache_env.sh" "${FIXTURE_ROOT}/src/scripts/normalize_pytest_addopts.sh"
}

copy_script_to_fixture() {
  local script_name="$1"
  local mapped_script_name="$script_name"
  case "$script_name" in
    06_run_av_test.sh) mapped_script_name="t01_run_av_test.sh" ;;
    05_run_dependency_freshness_tests.sh) mapped_script_name="t02_run_dependency_freshness_tests.sh" ;;
    07_run_static_security_tests.sh) mapped_script_name="t03_run_static_security_tests.sh" ;;
    00_run_requirements_traceability_tests.sh) mapped_script_name="t04_run_requirements_traceability_tests.sh" ;;
    09_deploy_database_verification_test.sh) mapped_script_name="t05_deploy_database_verification_test.sh" ;;
    13_run_sql_unit_tests.sh) mapped_script_name="t06_run_sql_unit_tests.sh" ;;
    10_run_shell_unit_tests.sh) mapped_script_name="t07_run_shell_unit_tests.sh" ;;
    11_run_python_unit_tests.sh) mapped_script_name="t08_run_python_unit_tests.sh" ;;
    12_run_mutation_tests.sh) mapped_script_name="t09_run_mutation_tests.sh" ;;
    15_run_swift_unit_tests.sh) mapped_script_name="t10_run_swift_unit_tests.sh" ;;
    14_run_fuzz_tests.sh) mapped_script_name="t11_run_fuzz_tests.sh" ;;
    23_run_dynamic_security_tests.sh) mapped_script_name="t12_run_dynamic_security_tests.sh" ;;
    18_run_teller_api_smoke_tests.sh) mapped_script_name="t13_run_teller_api_smoke_tests.sh" ;;
    16_run_macos_ui_regression_tests.sh) mapped_script_name="t14_run_macos_ui_regression_tests.sh" ;;
    17_verify_macos_crash_test.sh) mapped_script_name="t15_verify_macos_crash_test.sh" ;;
    22_classification_persistence_verification_test.sh) mapped_script_name="t16_classification_persistence_verification_test.sh" ;;
  esac
  local source_path
  source_path="$(repo_root)/${script_name}"
  if [[ ! -f "$source_path" && -f "$(repo_root)/tests/${script_name}" ]]; then
    source_path="$(repo_root)/tests/${script_name}"
  elif [[ ! -f "$source_path" && -f "$(repo_root)/tests/${mapped_script_name}" ]]; then
    source_path="$(repo_root)/tests/${mapped_script_name}"
  fi
  cp "$source_path" "${FIXTURE_ROOT}/${script_name}"
  chmod +x "${FIXTURE_ROOT}/${script_name}"
  case "$script_name" in
    07_run_static_security_tests.sh|12_run_mutation_tests.sh|14_run_fuzz_tests.sh|23_run_dynamic_security_tests.sh)
      copy_test_cache_env_scripts_to_fixture
      ;;
  esac
}

stub_cmd() {
  local name="$1"
  shift
  local target="${STUB_BIN}/${name}"
  {
    echo "#!/usr/bin/env bash"
    echo "echo ${name} \"\$*\" >> \"${CALLS_LOG}\""
    printf "%s\n" "$@"
  } > "$target"
  chmod +x "$target"
}

file_mode() {
  stat -f "%Lp" "$1"
}
