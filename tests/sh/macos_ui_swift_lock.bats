#!/usr/bin/env bats
load "helpers/common.bash"

setup() {
  setup_shell_test
}

teardown() {
  teardown_shell_test
}

@test "acquires lock and cleans it after command" {
  #R001-T01
  lock_file="${TEST_TMPDIR}/swift.lock"
  run bash -c "
    source '$(repo_root)/src/scripts/macos_ui_swift_lock.sh'
    macos_ui_with_swiftpm_lock '${lock_file}' 5 'unit-test' bash -c 'echo ok'
    [[ ! -d '${lock_file}.d' ]]
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "removes stale lock without pid marker" {
  #R005-T01
  lock_file="${TEST_TMPDIR}/swift.lock"
  mkdir -p "${lock_file}.d"
  run bash -c "
    source '$(repo_root)/src/scripts/macos_ui_swift_lock.sh'
    macos_ui_with_swiftpm_lock '${lock_file}' 5 'stale-lock' bash -c 'echo recovered'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing stale macOS UI SwiftPM lock"* ]]
  [[ "$output" == *"recovered"* ]]
}

@test "times out when lock stays held" {
  #R010-T01
  lock_file="${TEST_TMPDIR}/swift.lock"
  mkdir -p "${lock_file}.d"
  echo "$$" > "${lock_file}.d/pid"
  run bash -c "
    source '$(repo_root)/src/scripts/macos_ui_swift_lock.sh'
    MACOS_UI_SWIFT_LOCK_LOG_INTERVAL_SECONDS=1 \
      macos_ui_with_swiftpm_lock '${lock_file}' 1 'contention' bash -c 'echo never'
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timed out waiting for macOS UI SwiftPM lock"* ]]
}
