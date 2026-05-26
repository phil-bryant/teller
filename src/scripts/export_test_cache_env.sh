#!/usr/bin/env bash
# Export cache locations so pytest, ruff, Hypothesis, and bytecode caches stay under artifacts/cache/.
# Must be sourced (or called) before pytest/hypothesis import when possible.

#R001: Export canonical cache locations for Python test tooling.
#R005: Default Hypothesis storage away from repository-root .hypothesis.
export_test_cache_env() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(pwd)"
  fi
  if [[ "$repo_root" != /* ]]; then
    repo_root="$(cd "$repo_root" && pwd)"
  fi

  local cache_root="${repo_root}/artifacts/cache"

  export CACHE_ROOT="$cache_root"
  export PYTHONPYCACHEPREFIX="${cache_root}/pycache"
  export RUFF_CACHE_DIR="${cache_root}/ruff"
  export HYPOTHESIS_STORAGE_DIRECTORY="${cache_root}/hypothesis"
  mkdir -p "$PYTHONPYCACHEPREFIX" "$RUFF_CACHE_DIR" "$HYPOTHESIS_STORAGE_DIRECTORY" "${cache_root}/pytest"

  # shellcheck disable=SC1091
  source "${repo_root}/src/scripts/normalize_pytest_addopts.sh"
}
