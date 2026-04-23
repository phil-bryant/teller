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

copy_script_to_fixture() {
  local script_name="$1"
  cp "$(repo_root)/${script_name}" "${FIXTURE_ROOT}/${script_name}"
  chmod +x "${FIXTURE_ROOT}/${script_name}"
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
