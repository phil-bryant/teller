#!/usr/bin/env bash

#R001: Serialize SwiftPM operations with exclusive lock-directory protocol.
#R005: Detect and remove stale lock owners before waiting.
#R010: Enforce bounded wait with periodic lock contention diagnostics.
# Shared SwiftPM lock helper for scripts that touch ./src/macos-ui.
# Usage:
#   source ./src/scripts/macos_ui_swift_lock.sh
#   macos_ui_with_swiftpm_lock "<lock-file>" "<timeout-seconds>" "<context>" command arg1 arg2

macos_ui_with_swiftpm_lock() {
  if [[ "$#" -lt 4 ]]; then
    echo "❌ macos_ui_with_swiftpm_lock requires lock file, timeout, context, and command." >&2
    return 2
  fi

  local lock_file="$1"
  local timeout_seconds="$2"
  local wait_context="$3"
  shift 3

  if [[ -z "$lock_file" ]]; then
    echo "❌ macOS UI SwiftPM lock file path cannot be empty." >&2
    return 2
  fi
  if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$timeout_seconds" -le 0 ]]; then
    timeout_seconds=1
  fi

  local lock_dir="${lock_file}.d"
  local lock_parent_dir
  lock_parent_dir="$(dirname "$lock_file")"
  local log_interval_seconds="${MACOS_UI_SWIFT_LOCK_LOG_INTERVAL_SECONDS:-30}"
  if [[ ! "$log_interval_seconds" =~ ^[0-9]+$ ]] || [[ "$log_interval_seconds" -le 0 ]]; then
    log_interval_seconds=30
  fi

  mkdir -p "$lock_parent_dir"
  local start_ts now elapsed owner_pid next_log_elapsed
  start_ts="$(date +%s)"
  next_log_elapsed="$log_interval_seconds"

  while ! mkdir "$lock_dir" 2>/dev/null; do
    owner_pid=""
    if [[ -f "${lock_dir}/pid" ]]; then
      owner_pid="$(<"${lock_dir}/pid")"
      if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
        echo "ℹ️  Removing stale macOS UI SwiftPM lock (${lock_dir}); dead owner pid=${owner_pid}."
        rm -rf "$lock_dir"
        continue
      fi
    else
      echo "ℹ️  Removing stale macOS UI SwiftPM lock (${lock_dir}); pid marker missing."
      rm -rf "$lock_dir"
      continue
    fi

    now="$(date +%s)"
    elapsed=$((now - start_ts))
    if (( elapsed >= next_log_elapsed )); then
      if [[ -n "$owner_pid" ]]; then
        echo "⏳ Waiting on macOS UI SwiftPM lock (${wait_context}); held by pid=${owner_pid} for ${elapsed}s..."
      else
        echo "⏳ Waiting on macOS UI SwiftPM lock (${wait_context}) for ${elapsed}s..."
      fi
      next_log_elapsed=$((next_log_elapsed + log_interval_seconds))
    fi
    if (( elapsed >= timeout_seconds )); then
      if [[ -n "$owner_pid" ]]; then
        echo "❌ Timed out waiting for macOS UI SwiftPM lock at ${lock_dir} after ${elapsed}s (holder pid=${owner_pid}, context=${wait_context})." >&2
      else
        echo "❌ Timed out waiting for macOS UI SwiftPM lock at ${lock_dir} after ${elapsed}s (context=${wait_context})." >&2
      fi
      return 1
    fi
    sleep 1
  done

  (
    trap 'rm -rf "$lock_dir"' EXIT INT TERM
    echo "${BASHPID:-$$}" > "${lock_dir}/pid"
    "$@"
  )
  return $?
}
