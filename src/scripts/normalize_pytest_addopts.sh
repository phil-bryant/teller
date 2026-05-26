#!/usr/bin/env bash
# Strip invalid pytest --cache-dir CLI flags from PYTEST_ADDOPTS.
# pytest expects cache_dir via pyproject.toml or -o cache_dir=..., not --cache-dir=.

#R001: Leave PYTEST_ADDOPTS unchanged when no invalid --cache-dir flag is present.
#R005: Strip invalid --cache-dir from PYTEST_ADDOPTS and warn the operator.
normalize_pytest_addopts() {
  if [[ "${PYTEST_ADDOPTS:-}" != *"--cache-dir="* ]]; then
    return 0
  fi
  echo "⚠️  Stripping invalid --cache-dir from PYTEST_ADDOPTS (use pyproject.toml cache_dir or -o cache_dir=...)." >&2
  PYTEST_ADDOPTS="$(printf '%s' "$PYTEST_ADDOPTS" | sed -E 's/--cache-dir=[^ ]+//g; s/  +/ /g; s/^ //; s/ $//')"
  if [[ -z "${PYTEST_ADDOPTS}" ]]; then
    unset PYTEST_ADDOPTS
  else
    export PYTEST_ADDOPTS
  fi
}

normalize_pytest_addopts
