#!/usr/bin/env bash

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd
}

setup_shell_test() {
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export HOME="${TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  unset RUNBOOK_REPO_ROOT

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

copy_security_lane_assets_to_fixture() {
  mkdir -p "${FIXTURE_ROOT}/src/scripts/security"
  cp "$(repo_root)/src/scripts/security/common.sh" "${FIXTURE_ROOT}/src/scripts/security/common.sh"
  cp "$(repo_root)/src/scripts/security/run_static_security_lane.sh" "${FIXTURE_ROOT}/src/scripts/security/run_static_security_lane.sh"
  cp "$(repo_root)/src/scripts/security/run_dynamic_security_lane.sh" "${FIXTURE_ROOT}/src/scripts/security/run_dynamic_security_lane.sh"
  chmod +x \
    "${FIXTURE_ROOT}/src/scripts/security/common.sh" \
    "${FIXTURE_ROOT}/src/scripts/security/run_static_security_lane.sh" \
    "${FIXTURE_ROOT}/src/scripts/security/run_dynamic_security_lane.sh"

  mkdir -p "${FIXTURE_ROOT}/tests/py/security"
  cp "$(repo_root)/tests/py/security/__init__.py" "${FIXTURE_ROOT}/tests/py/security/__init__.py"
  cp "$(repo_root)/tests/py/security/category_integrity_check.py" "${FIXTURE_ROOT}/tests/py/security/category_integrity_check.py"
  cp "$(repo_root)/tests/py/security/delete_category_contract_check.py" "${FIXTURE_ROOT}/tests/py/security/delete_category_contract_check.py"
  cp "$(repo_root)/tests/py/security/sast_summary_gate.py" "${FIXTURE_ROOT}/tests/py/security/sast_summary_gate.py"
  cp "$(repo_root)/tests/py/security/schemathesis_fixture_prep.py" "${FIXTURE_ROOT}/tests/py/security/schemathesis_fixture_prep.py"
  cp "$(repo_root)/tests/py/security/zap_summary_parser.py" "${FIXTURE_ROOT}/tests/py/security/zap_summary_parser.py"
}

copy_traceability_assets_to_fixture() {
  mkdir -p "${FIXTURE_ROOT}/tests/py/traceability"
  cp "$(repo_root)/tests/py/traceability/__init__.py" "${FIXTURE_ROOT}/tests/py/traceability/__init__.py"
  cp "$(repo_root)/tests/py/traceability/cli.py" "${FIXTURE_ROOT}/tests/py/traceability/cli.py"
  cp "$(repo_root)/tests/py/traceability/discovery.py" "${FIXTURE_ROOT}/tests/py/traceability/discovery.py"
  cp "$(repo_root)/tests/py/traceability/parsing.py" "${FIXTURE_ROOT}/tests/py/traceability/parsing.py"
  cp "$(repo_root)/tests/py/traceability/verification.py" "${FIXTURE_ROOT}/tests/py/traceability/verification.py"
}

copy_script_to_fixture() {
  local script_name="$1"
  local root_dir runner_dir source_path candidate
  root_dir="$(repo_root)"
  runner_dir="${root_dir}/../runner"
  source_path=""
  for candidate in \
    "${root_dir}/${script_name}" \
    "${root_dir}/tests/${script_name}" \
    "${runner_dir}/${script_name}"; do
    if [[ -f "$candidate" ]]; then
      source_path="$candidate"
      break
    fi
  done
  if [[ -z "$source_path" ]]; then
    echo "❌ Unable to locate script fixture source for '${script_name}'." >&2
    echo "Checked: ${root_dir}/${script_name}" >&2
    echo "Checked: ${root_dir}/tests/${script_name}" >&2
    echo "Checked: ${runner_dir}/${script_name}" >&2
    return 1
  fi
  cp "$source_path" "${FIXTURE_ROOT}/${script_name}"
  chmod +x "${FIXTURE_ROOT}/${script_name}"
  case "$script_name" in
    t03_run_static_security_tests.sh|t09_run_mutation_tests.sh|t11_run_fuzz_tests.sh|t12_run_dynamic_security_tests.sh)
      copy_test_cache_env_scripts_to_fixture
      ;;
  esac
  case "$script_name" in
    t03_run_static_security_tests.sh|t12_run_dynamic_security_tests.sh)
      copy_security_lane_assets_to_fixture
      ;;
  esac
  case "$script_name" in
    t04_run_requirements_traceability_tests.sh)
      copy_traceability_assets_to_fixture
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
