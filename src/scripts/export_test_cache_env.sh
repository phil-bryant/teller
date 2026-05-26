#!/usr/bin/env bash
# Export cache locations so pytest, ruff, Hypothesis, and bytecode caches stay under artifacts/cache/.
# Must be sourced (or called) before pytest/hypothesis import when possible.

export_test_cache_env() {
  local repo_root="${1:-}"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(pwd)"
  fi
  if [[ "$repo_root" != /* ]]; then
    repo_root="$(cd "$repo_root" && pwd)"
  fi

  local cache_root="${CACHE_ROOT:-${repo_root}/artifacts/cache}"
  if [[ "$cache_root" != /* ]]; then
    cache_root="${repo_root}/${cache_root#./}"
  fi

  export CACHE_ROOT="$cache_root"
  export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-${cache_root}/pycache}"
  export RUFF_CACHE_DIR="${RUFF_CACHE_DIR:-${cache_root}/ruff}"
  export HYPOTHESIS_STORAGE_DIRECTORY="${HYPOTHESIS_STORAGE_DIRECTORY:-${cache_root}/hypothesis}"
  mkdir -p "$PYTHONPYCACHEPREFIX" "$RUFF_CACHE_DIR" "$HYPOTHESIS_STORAGE_DIRECTORY" "${cache_root}/pytest"
}
