#!/usr/bin/env bash
# Append teller cache-env exports to a venv activate script (idempotent).

#R001: Append teller cache-env exports to a venv activate script idempotently.
#R005: Fail when the venv activate script is missing.
install_venv_test_cache_env() {
  local venv_dir="${1:?venv directory required}"
  local activate_script="${venv_dir}/bin/activate"
  local marker='# >>> teller test cache env >>>'

  if [[ ! -f "$activate_script" ]]; then
    echo "❌ activate script not found: ${activate_script}" >&2
    return 1
  fi
  if grep -Fq "$marker" "$activate_script" 2>/dev/null; then
    return 0
  fi

  cat >>"$activate_script" <<'EOF'

# >>> teller test cache env >>>
_teller_repo_root_for_cache() {
  local dir="${PWD}"
  while [[ -n "${dir}" && "${dir}" != "/" ]]; do
    if [[ -f "${dir}/pyproject.toml" && -f "${dir}/src/scripts/export_test_cache_env.sh" ]]; then
      printf '%s\n' "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  return 1
}
if [[ -z "${TELLER_SKIP_VENV_CACHE_ENV:-}" ]]; then
  _teller_repo_root="$(_teller_repo_root_for_cache || true)"
  if [[ -n "${_teller_repo_root}" ]]; then
    # shellcheck disable=SC1091
    . "${_teller_repo_root}/src/scripts/export_test_cache_env.sh"
    export_test_cache_env "${_teller_repo_root}"
  fi
  unset _teller_repo_root
fi
unset -f _teller_repo_root_for_cache
# <<< teller test cache env <<<
EOF
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  install_venv_test_cache_env "$@" || exit $?
fi
